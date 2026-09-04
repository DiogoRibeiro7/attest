#' Create a check result
#'
#' Every check returns one of these. `status` is one of `"pass"`, `"fail"`,
#' `"waived"`, `"untestable"` or `"info"`.
#'
#' @param id Check identifier.
#' @param status One of `"pass"`, `"fail"`, `"waived"`, `"untestable"`, `"info"`.
#' @param statistic Numeric statistic (may be `NA`).
#' @param threshold Numeric threshold (may be `NA`).
#' @param message Human-readable summary.
#' @param evidence Optional list of supporting objects.
#' @return An object of class `attest_result`.
#' @export
attest_result <- function(id, status, statistic = NA_real_, threshold = NA_real_,
                          message = "", evidence = list()) {
  status <- match.arg(status, c("pass", "fail", "waived", "untestable", "info"))
  structure(
    list(id = id, status = status, statistic = statistic,
         threshold = threshold, message = message, evidence = evidence),
    class = "attest_result"
  )
}

#' Define a new check
#'
#' Checks are the extension point of attest. A check is a function
#' `run(ctx)` receiving a context list with `train`, `test`, `calib`,
#' `model`, `task`, `outcome`, `features`, `spec` and returning an
#' [attest_result()].
#'
#' @param id Unique identifier.
#' @param run Function of one argument (the context list).
#' @param blocking If `TRUE` a `"fail"` blocks certification.
#' @param stage One of `"pre"` (before fitting; sees only data) or `"post"`
#'   (after fitting; sees the model).
#' @return An object of class `attest_check`.
#' @export
new_check <- function(id, run, blocking = TRUE, stage = c("pre", "post")) {
  stage <- match.arg(stage)
  stopifnot(is.character(id), length(id) == 1, is.function(run))
  structure(list(id = id, run = run, blocking = blocking, stage = stage),
            class = "attest_check")
}

#' @export
print.attest_check <- function(x, ...) {
  cat("<attest_check> ", x$id, " [", x$stage, if (x$blocking) ", blocking" else "", "]\n", sep = "")
  invisible(x)
}

# ---- Leakage checks --------------------------------------------------------

#' Leakage check: exact duplicate rows across train and test
#'
#' @param max_prop Maximum tolerated proportion of test rows that are exact
#'   duplicates of training rows.
#' @return An `attest_check`.
#' @export
leak_duplicates <- function(max_prop = 0) {
  new_check("leak_duplicates", stage = "pre", run = function(ctx) {
    keys_tr <- do.call(paste, c(ctx$train[ctx$features], sep = "\r"))
    keys_te <- do.call(paste, c(ctx$test[ctx$features], sep = "\r"))
    prop <- mean(keys_te %in% keys_tr)
    attest_result(
      "leak_duplicates",
      if (prop <= max_prop) "pass" else "fail",
      statistic = prop, threshold = max_prop,
      message = sprintf("%.1f%% of test rows duplicate a training row", 100 * prop)
    )
  })
}

#' Leakage check: a single feature is a near-deterministic proxy of the target
#'
#' For each feature, a one-variable model is fitted on the training set. For
#' classification the statistic is accuracy; for regression it is R-squared.
#' Any feature above `threshold` fails the check.
#'
#' @param threshold Maximum tolerated single-feature accuracy / R-squared.
#' @return An `attest_check`.
#' @export
leak_target_proxy <- function(threshold = 0.95) {
  new_check("leak_target_proxy", stage = "pre", run = function(ctx) {
    y <- ctx$train[[ctx$outcome]]
    scores <- vapply(ctx$features, function(f) {
      x <- ctx$train[[f]]
      if (length(unique(x)) < 2) return(0)
      d <- data.frame(y = y, x = x)
      if (ctx$task == "classification") {
        fit <- tryCatch(stats::glm(y ~ x, data = d, family = stats::binomial()),
                        error = function(e) NULL, warning = function(w) NULL)
        if (is.null(fit)) {
          # perfect separation etc. -- treat as proxy
          return(1)
        }
        p <- stats::predict(fit, type = "response")
        mean((p > 0.5) == (as.integer(y) == 2L))
      } else {
        fit <- tryCatch(stats::lm(y ~ x, data = d), error = function(e) NULL)
        if (is.null(fit)) return(0)
        summary(fit)$r.squared
      }
    }, numeric(1))
    bad <- names(scores)[scores > threshold]
    attest_result(
      "leak_target_proxy",
      if (length(bad) == 0) "pass" else "fail",
      statistic = max(scores), threshold = threshold,
      message = if (length(bad) == 0)
        sprintf("max single-feature score %.3f", max(scores))
      else sprintf("proxy features: %s", paste(bad, collapse = ", ")),
      evidence = list(scores = scores)
    )
  })
}

#' Leakage check: test rows must not precede training rows in time
#'
#' @param time Name of the time column.
#' @param max_prop Maximum tolerated proportion of test rows dated before the
#'   last training row.
#' @return An `attest_check`.
#' @export
leak_temporal <- function(time, max_prop = 0) {
  new_check("leak_temporal", stage = "pre", run = function(ctx) {
    if (!time %in% names(ctx$train)) {
      return(attest_result("leak_temporal", "untestable",
                           message = sprintf("column `%s` not found", time)))
    }
    last_train <- max(ctx$train[[time]], na.rm = TRUE)
    prop <- mean(ctx$test[[time]] < last_train, na.rm = TRUE)
    attest_result(
      "leak_temporal",
      if (prop <= max_prop) "pass" else "fail",
      statistic = prop, threshold = max_prop,
      message = sprintf("%.1f%% of test rows precede last training row", 100 * prop)
    )
  })
}

# ---- Informational checks --------------------------------------------------

#' Class imbalance report (informational, never blocks)
#'
#' @return An `attest_check`.
#' @export
imbalance_report <- function() {
  new_check("imbalance_report", stage = "pre", blocking = FALSE, run = function(ctx) {
    if (ctx$task != "classification") {
      return(attest_result("imbalance_report", "untestable", message = "regression task"))
    }
    tab <- table(ctx$train[[ctx$outcome]])
    ratio <- min(tab) / max(tab)
    attest_result("imbalance_report", "info", statistic = ratio,
                  message = sprintf("minority/majority ratio %.3f (%s)", ratio,
                                    paste(names(tab), tab, sep = "=", collapse = ", ")),
                  evidence = list(table = tab))
  })
}

# ---- Post-fit checks -------------------------------------------------------

#' Calibration check: expected calibration error on the test set
#'
#' @param max Maximum tolerated ECE.
#' @param bins Number of equal-width probability bins.
#' @return An `attest_check`.
#' @export
calib_ece <- function(max = 0.1, bins = 10) {
  new_check("calib_ece", stage = "post", run = function(ctx) {
    if (ctx$task != "classification") {
      return(attest_result("calib_ece", "untestable", message = "regression task"))
    }
    p <- engine_predict(ctx$engine, ctx$model, ctx$test, type = "prob")
    y <- as.integer(ctx$test[[ctx$outcome]]) == 2L
    ece <- ece_stat(p, y, bins)
    attest_result("calib_ece", if (ece <= max) "pass" else "fail",
                  statistic = ece, threshold = max,
                  message = sprintf("ECE = %.3f (max %.3f)", ece, max))
  })
}

ece_stat <- function(p, y, bins) {
  b <- cut(p, breaks = seq(0, 1, length.out = bins + 1), include.lowest = TRUE)
  n <- length(p)
  ece <- 0
  for (lv in levels(b)) {
    idx <- which(b == lv)
    if (length(idx) == 0) next
    ece <- ece + (length(idx) / n) * abs(mean(y[idx]) - mean(p[idx]))
  }
  ece
}

#' Coverage check: split conformal prediction
#'
#' Calibrates a nonconformity quantile on the held-out calibration set and
#' verifies empirical coverage on the test set. For regression the score is
#' the absolute residual and predictions carry an interval; for binary
#' classification the score is `1 - p(true class)` and predictions carry a
#' label set.
#'
#' @param alpha Miscoverage level; target coverage is `1 - alpha`.
#' @param tolerance Tolerated shortfall of empirical test coverage below
#'   `1 - alpha` before the check fails.
#' @return An `attest_check`.
#' @export
conformal_split <- function(alpha = 0.1, tolerance = 0.03) {
  new_check("conformal_split", stage = "post", run = function(ctx) {
    scores <- conformal_scores(ctx$engine, ctx$model, ctx$calib, ctx$outcome, ctx$task)
    n <- length(scores)
    k <- ceiling((n + 1) * (1 - alpha))
    q <- if (k > n) Inf else sort(scores)[k]
    test_scores <- conformal_scores(ctx$engine, ctx$model, ctx$test, ctx$outcome, ctx$task)
    cov <- mean(test_scores <= q)
    attest_result(
      "conformal_split",
      if (cov >= 1 - alpha - tolerance) "pass" else "fail",
      statistic = cov, threshold = 1 - alpha,
      message = sprintf("empirical coverage %.3f (target %.3f)", cov, 1 - alpha),
      evidence = list(q = q, alpha = alpha, n_calib = n)
    )
  })
}

conformal_scores <- function(engine, model, data, outcome, task) {
  if (task == "classification") {
    p <- engine_predict(engine, model, data, type = "prob")
    y <- as.integer(data[[outcome]]) == 2L
    ifelse(y, 1 - p, p)
  } else {
    yhat <- engine_predict(engine, model, data, type = "numeric")
    abs(data[[outcome]] - yhat)
  }
}

#' Shift monitor: population stability index baseline
#'
#' Stores training-set bin edges and frequencies per feature. At prediction
#' time the batch PSI is computed per feature; batches with any feature above
#' `threshold` are flagged. Rows with a numeric feature outside the training
#' support (widened by `support_tol` times the range) or with an unseen factor
#' level are refused.
#'
#' @param threshold PSI above which a batch is flagged.
#' @param bins Number of quantile bins for numeric features.
#' @param support_tol Relative widening of the training range for the support
#'   check.
#' @param min_batch Minimum number of rows in a prediction batch for the batch
#'   PSI to be computed; smaller batches are only subject to the support check.
#' @return An `attest_check`.
#' @export
shift_monitor <- function(threshold = 0.2, bins = 10, support_tol = 0.05, min_batch = 50) {
  new_check("shift_monitor", stage = "post", blocking = FALSE, run = function(ctx) {
    baseline <- lapply(ctx$features, function(f) {
      x <- ctx$train[[f]]
      if (is.numeric(x)) {
        br <- unique(stats::quantile(x, probs = seq(0, 1, length.out = bins + 1), na.rm = TRUE))
        if (length(br) < 2) br <- c(min(x), max(x) + 1e-8)
        freq <- as.numeric(table(cut(x, br, include.lowest = TRUE))) / length(x)
        rng <- range(x, na.rm = TRUE)
        pad <- support_tol * diff(rng)
        list(type = "numeric", breaks = br, freq = freq,
             support = c(rng[1] - pad, rng[2] + pad))
      } else {
        lv <- levels(as.factor(x))
        freq <- as.numeric(table(factor(x, levels = lv))) / length(x)
        list(type = "categorical", levels = lv, freq = freq)
      }
    })
    names(baseline) <- ctx$features
    attest_result("shift_monitor", "info", threshold = threshold,
                  message = "baseline stored",
                  evidence = list(baseline = baseline, threshold = threshold,
                                  min_batch = min_batch))
  })
}

psi <- function(expected, actual, eps = 1e-4) {
  e <- pmax(expected, eps); a <- pmax(actual, eps)
  sum((a - e) * log(a / e))
}
