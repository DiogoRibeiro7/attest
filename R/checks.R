#' Create a check result
#'
#' Every check returns one of these. `status` is one of `"pass"`, `"weak"`,
#' `"fail"`, `"waived"`, `"untestable"` or `"info"`.
#'
#' `"weak"` means the statistic's confidence interval straddles the threshold:
#' the check neither confidently passed nor confidently failed. See
#' [attest_verdict()].
#'
#' @param id Check identifier.
#' @param status One of `"pass"`, `"weak"`, `"fail"`, `"waived"`,
#'   `"untestable"`, `"info"`.
#' @param statistic Numeric statistic (may be `NA`).
#' @param threshold Numeric threshold (may be `NA`).
#' @param ci Numeric vector of length 2, the lower and upper bounds of a
#'   confidence interval for `statistic`. `c(NA, NA)` when not estimated.
#' @param message Human-readable summary.
#' @param evidence Optional list of supporting objects.
#' @param label Human-readable check label. When omitted, a label is derived
#'   from `id`.
#' @return An object of class `attest_result`.
#' @family checks
#' @examples
#' attest_result("my_check", "weak",
#'   statistic = 0.04,
#'   threshold = 0.05, ci = c(0.02, 0.09)
#' )
#' @export
attest_result <- function(id, status, statistic = NA_real_, threshold = NA_real_,
                          ci = c(NA_real_, NA_real_), message = "",
                          evidence = list(), label = NULL) {
  status <- match.arg(status, c("pass", "weak", "fail", "waived", "untestable", "info"))
  if (length(ci) != 2) rlang::abort("`ci` must have length 2")
  structure(
    list(
      id = id, label = check_label(id, label), status = status, statistic = statistic,
      threshold = threshold, ci = as.numeric(ci),
      message = message, evidence = evidence
    ),
    class = "attest_result"
  )
}

#' Bootstrap a confidence interval for a check statistic
#'
#' Resamples row indices with replacement and recomputes the statistic, giving
#' a percentile interval. Checks use this so that a threshold comparison
#' accounts for sampling noise rather than resting on a point estimate.
#'
#' @param stat Function of one argument, an integer vector of row indices,
#'   returning a single number.
#' @param n Number of rows to resample from.
#' @param n_boot Number of bootstrap replicates. `0` disables estimation and
#'   returns `c(NA, NA)`.
#' @param conf Confidence level.
#' @return A numeric vector of length 2.
#' @family checks
#' @examples
#' y <- rbinom(200, 1, 0.3)
#' attest_boot(function(i) mean(y[i]), n = length(y), n_boot = 200)
#' @export
attest_boot <- function(stat, n, n_boot = 1000, conf = 0.95) {
  if (n_boot < 2 || n < 2) {
    return(c(NA_real_, NA_real_))
  }
  reps <- vapply(seq_len(n_boot), function(b) {
    tryCatch(as.numeric(stat(sample.int(n, n, replace = TRUE))),
      error = function(e) NA_real_
    )
  }, numeric(1))
  reps <- reps[is.finite(reps)]
  if (length(reps) < 2) {
    return(c(NA_real_, NA_real_))
  }
  a <- (1 - conf) / 2
  unname(stats::quantile(reps, c(a, 1 - a), names = FALSE, na.rm = TRUE))
}

#' Decide a check verdict from an interval and a threshold
#'
#' Implements the rule that a check fails only when the whole confidence
#' interval clears the threshold, so that noise alone cannot fail a check.
#' When the interval straddles the threshold the verdict is `"weak"`: the
#' evidence does not settle the question either way.
#'
#' If `ci` is `c(NA, NA)` the point estimate decides, and `"weak"` is never
#' returned.
#'
#' @param statistic The point estimate.
#' @param ci Confidence interval for `statistic`, length 2.
#' @param threshold The threshold to compare against.
#' @param direction `"at_most"` when the statistic should not exceed the
#'   threshold (ECE, PSI), `"at_least"` when it should not fall below it
#'   (coverage).
#' @return One of `"pass"`, `"weak"`, `"fail"`.
#' @family checks
#' @examples
#' attest_verdict(0.04, c(0.02, 0.09), threshold = 0.05, direction = "at_most")
#' attest_verdict(0.04, c(0.02, 0.045), threshold = 0.05, direction = "at_most")
#' @export
attest_verdict <- function(statistic, ci, threshold,
                           direction = c("at_most", "at_least")) {
  direction <- match.arg(direction)
  if (length(ci) != 2 || anyNA(ci)) {
    ok <- if (direction == "at_most") statistic <= threshold else statistic >= threshold
    return(if (ok) "pass" else "fail")
  }
  if (direction == "at_most") {
    if (ci[1] > threshold) "fail" else if (ci[2] <= threshold) "pass" else "weak"
  } else {
    if (ci[2] < threshold) "fail" else if (ci[1] >= threshold) "pass" else "weak"
  }
}

fmt_ci <- function(ci) {
  if (length(ci) != 2 || anyNA(ci)) {
    return("")
  }
  sprintf(" [%.3f, %.3f]", ci[1], ci[2])
}

# Base R gained `%||%` in 4.4.0; the package supports 4.1.
`%||%` <- function(x, y) if (is.null(x)) y else x

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
#' @param label Human-readable label used in console output, certificates and
#'   reports. Defaults to a title-cased version of `id`.
#' @return An object of class `attest_check`.
#' @family checks
#' @examples
#' # a check that refuses training data with too many missing cells
#' max_missing <- new_check("max_missing", stage = "pre", run = function(ctx) {
#'   prop <- mean(is.na(ctx$train[ctx$features]))
#'   attest_result("max_missing", if (prop <= 0.05) "pass" else "fail",
#'     statistic = prop, threshold = 0.05
#'   )
#' })
#' max_missing
#' @export
new_check <- function(id, run, blocking = TRUE, stage = c("pre", "post"),
                      label = NULL) {
  stage <- match.arg(stage)
  stopifnot(is.character(id), length(id) == 1, is.function(run))
  structure(
    list(
      id = id, label = check_label(id, label),
      run = run, blocking = blocking, stage = stage
    ),
    class = "attest_check"
  )
}

check_label <- function(id, label = NULL) {
  if (!is.null(label)) {
    stopifnot(is.character(label), length(label) == 1, nzchar(label))
    return(label)
  }
  known <- c(
    leak_duplicates = "Duplicate row leakage",
    leak_target_proxy = "Target proxy leakage",
    leak_temporal = "Temporal leakage",
    imbalance_report = "Class imbalance",
    calib_ece = "Calibration error",
    conformal_split = "Conformal coverage",
    shift_monitor = "Population stability shift",
    shift_c2st = "Classifier two-sample shift"
  )
  if (id %in% names(known)) {
    return(unname(known[[id]]))
  }
  words <- strsplit(gsub("_+", " ", id), " +", fixed = FALSE)[[1]]
  words <- words[nzchar(words)]
  if (!length(words)) {
    return(id)
  }
  words[1] <- paste0(toupper(substr(words[1], 1, 1)), substr(words[1], 2, nchar(words[1])))
  paste(words, collapse = " ")
}

#' @export
print.attest_check <- function(x, ...) {
  cat("<attest_check> ", x$label, " <", x$id, ">",
    " [", x$stage, if (x$blocking) ", blocking" else "", "]\n",
    sep = ""
  )
  invisible(x)
}

# ---- Leakage checks --------------------------------------------------------

#' Leakage check: exact duplicate rows across train and test
#'
#' @param max_prop Maximum tolerated proportion of test rows that are exact
#'   duplicates of training rows.
#' @details
#' Unlike [calib_ece()] or [conformal_split()], this check reports no
#' confidence interval. Duplication is a census of the rows you actually hold,
#' not an estimate of a population quantity: if a training row appears in the
#' test set, it is there, and resampling would only describe a hypothetical
#' other dataset. The same reasoning applies to [leak_temporal()].
#' @return An `attest_check`.
#' @family leakage checks
#' @examples
#' leak_duplicates()
#' # tolerate a small overlap
#' leak_duplicates(max_prop = 0.01)
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
#' @param n_boot Bootstrap replicates for the confidence interval on the
#'   strongest feature's score; `0` disables it and the point estimate
#'   decides.
#' @details
#' The reported statistic is the maximum score across features. It is given a
#' bootstrap confidence interval over training rows, so a feature that merely
#' looks strong in a small sample no longer fails the check outright: the
#' verdict is `"weak"` unless the whole interval sits above `threshold`.
#'
#' Bootstrapping is conditional on the fitted one-variable models -- they are
#' fitted once, and resampling is applied to their per-row predictions rather
#' than refitting each replicate. This keeps the check affordable and captures
#' sampling noise in the score, but not the variability of the fits themselves.
#' @return An `attest_check`.
#' @family leakage checks
#' @examples
#' leak_target_proxy()
#' # a stricter bar, with the interval disabled
#' leak_target_proxy(threshold = 0.9, n_boot = 0)
#' @export
leak_target_proxy <- function(threshold = 0.95, n_boot = 500) {
  new_check("leak_target_proxy", stage = "pre", run = function(ctx) {
    y <- ctx$train[[ctx$outcome]]
    n <- length(y)
    classification <- is_classification(ctx$task)
    multiclass <- identical(ctx$task, "multiclass")
    yb <- if (classification) as.integer(y) == 2L else as.numeric(y)

    # Per-row contribution for each feature: a hit/miss indicator for
    # classification, a fitted value for regression. Keeping these lets the
    # max-over-features score be resampled without refitting.
    contrib <- vapply(ctx$features, function(f) {
      x <- ctx$train[[f]]
      if (length(unique(x)) < 2) {
        return(if (classification) rep(0, n) else rep(mean(yb), n))
      }
      if (multiclass) {
        h <- stump_hits(x, y)
        return(if (is.null(h)) rep(0, n) else h)
      }
      d <- data.frame(y = y, x = x)
      if (classification) {
        fit <- tryCatch(stats::glm(y ~ x, data = d, family = stats::binomial()),
          error = function(e) NULL, warning = function(w) NULL
        )
        # Perfect separation cannot be fitted but is itself proxy evidence,
        # so every row counts as a hit.
        if (is.null(fit)) {
          return(rep(1, n))
        }
        as.numeric((stats::predict(fit, type = "response") > 0.5) == yb)
      } else {
        fit <- tryCatch(stats::lm(y ~ x, data = d), error = function(e) NULL)
        if (is.null(fit)) {
          return(rep(mean(yb), n))
        }
        as.numeric(stats::fitted(fit))
      }
    }, numeric(n))
    contrib <- matrix(contrib, nrow = n, dimnames = list(NULL, ctx$features))

    score_on <- function(i) {
      if (classification) {
        return(colMeans(contrib[i, , drop = FALSE]))
      }
      sst <- sum((yb[i] - mean(yb[i]))^2)
      if (sst <= 0) {
        return(rep(0, ncol(contrib)))
      }
      sse <- colSums((yb[i] - contrib[i, , drop = FALSE])^2)
      pmax(0, 1 - sse / sst)
    }

    scores <- score_on(seq_len(n))
    names(scores) <- ctx$features
    top <- max(scores)
    ci <- attest_boot(function(i) max(score_on(i)), n, n_boot)
    status <- attest_verdict(top, ci, threshold, "at_most")
    bad <- names(scores)[scores > threshold]
    attest_result(
      "leak_target_proxy", status,
      statistic = top, threshold = threshold, ci = ci,
      message = if (length(bad) == 0) {
        sprintf("max single-feature score %.3f%s", top, fmt_ci(ci))
      } else {
        sprintf(
          "proxy features: %s (max %.3f%s)",
          paste(bad, collapse = ", "), top, fmt_ci(ci)
        )
      },
      evidence = list(scores = scores, ci = ci)
    )
  })
}

#' Leakage check: test rows must not precede training rows in time
#'
#' @param time Name of the time column.
#' @param max_prop Maximum tolerated proportion of test rows dated before the
#'   last training row.
#' @return An `attest_check`.
#' @family leakage checks
#' @examples
#' leak_temporal("order_date")
#' @export
leak_temporal <- function(time, max_prop = 0) {
  new_check("leak_temporal", stage = "pre", run = function(ctx) {
    if (!time %in% names(ctx$train)) {
      return(attest_result("leak_temporal", "untestable",
        message = sprintf("column `%s` not found", time)
      ))
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
#' @family checks
#' @examples
#' imbalance_report()
#' @export
imbalance_report <- function() {
  new_check("imbalance_report", stage = "pre", blocking = FALSE, run = function(ctx) {
    if (!is_classification(ctx$task)) {
      return(attest_result("imbalance_report", "untestable", message = "regression task"))
    }
    tab <- table(ctx$train[[ctx$outcome]])
    ratio <- min(tab) / max(tab)
    attest_result("imbalance_report", "info",
      statistic = ratio,
      message = sprintf(
        "minority/majority ratio %.3f (%s)", ratio,
        paste(names(tab), tab, sep = "=", collapse = ", ")
      ),
      evidence = list(table = tab)
    )
  })
}

# ---- Post-fit checks -------------------------------------------------------

#' Calibration check: expected calibration error on the test set
#'
#' The ECE is a sample statistic, so it is reported with a bootstrap
#' confidence interval over test rows and the verdict follows
#' [attest_verdict()]: the check fails only when the whole interval sits above
#' `max`, and is `"weak"` when the interval straddles it.
#'
#' @param max Maximum tolerated ECE.
#' @param bins Number of equal-width probability bins.
#' @param n_boot Bootstrap replicates for the confidence interval; `0`
#'   disables it and the point estimate decides.
#' @return An `attest_check`.
#' @family calibration checks
#' @examples
#' calib_ece()
#' calib_ece(max = 0.05, bins = 20)
#' @export
calib_ece <- function(max = 0.1, bins = 10, n_boot = 1000) {
  new_check("calib_ece", stage = "post", run = function(ctx) {
    if (!is_classification(ctx$task)) {
      return(attest_result("calib_ece", "untestable", message = "regression task"))
    }
    if (ctx$task == "multiclass") {
      # Top-label ECE: bin by the confidence given to the predicted class and
      # compare it with how often that class is right.
      pm <- engine_predict(ctx$engine, ctx$model, ctx$test, type = "prob_matrix")
      p <- apply(pm, 1, max)
      y <- max.col(pm, ties.method = "first") ==
        as.integer(ctx$test[[ctx$outcome]])
    } else {
      p <- engine_predict(ctx$engine, ctx$model, ctx$test, type = "prob")
      y <- as.integer(ctx$test[[ctx$outcome]]) == 2L
    }
    ece <- ece_stat(p, y, bins)
    ci <- attest_boot(function(i) ece_stat(p[i], y[i], bins), length(p), n_boot)
    attest_result("calib_ece",
      attest_verdict(ece, ci, max, "at_most"),
      statistic = ece, threshold = max, ci = ci,
      message = sprintf("ECE = %.3f%s (max %.3f)", ece, fmt_ci(ci), max),
      evidence = list(bins = ece_bins(p, y, bins))
    )
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

# Per-bin confidence against observed frequency. Stored in the certificate so a
# reliability diagram can be drawn from the certificate alone, keeping the rule
# that a report never consults anything the model card cannot vouch for.
ece_bins <- function(p, y, bins) {
  b <- cut(p, breaks = seq(0, 1, length.out = bins + 1), include.lowest = TRUE)
  out <- lapply(levels(b), function(lv) {
    idx <- which(b == lv)
    if (!length(idx)) {
      return(NULL)
    }
    list(
      confidence = mean(p[idx]), observed = mean(y[idx]),
      n = length(idx)
    )
  })
  out <- Filter(Negate(is.null), out)
  if (!length(out)) {
    return(NULL)
  }
  list(
    confidence = vapply(out, function(z) z$confidence, numeric(1)),
    observed = vapply(out, function(z) z$observed, numeric(1)),
    n = vapply(out, function(z) z$n, numeric(1))
  )
}

# Empirical coverage the split conformal quantile would have achieved across a
# grid of miscoverage levels, so the card can show the whole curve rather than
# the single point the model was certified at.
coverage_curve <- function(calib_scores, test_scores,
                           alphas = seq(0.01, 0.5, by = 0.01)) {
  n <- length(calib_scores)
  if (!n || !length(test_scores)) {
    return(NULL)
  }
  s <- sort(calib_scores)
  cov <- vapply(alphas, function(a) {
    k <- ceiling((n + 1) * (1 - a))
    q <- if (k > n) Inf else s[k]
    mean(test_scores <= q)
  }, numeric(1))
  list(alpha = alphas, coverage = cov)
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
#' @param n_boot Bootstrap replicates for the coverage confidence interval;
#'   `0` disables it and the point estimate decides.
#' @param weighted If `TRUE`, store the calibration scores and covariates in
#'   the certificate so that [predict.attested_model()] can reweight them by an
#'   estimated covariate density ratio, widening intervals on batches that have
#'   drifted. See [attest_weighted_quantile()] for the guarantee this targets
#'   and its limits. The stored calibration set is what makes the certificate
#'   larger, so this is off by default.
#' @details
#' Empirical coverage is a sample statistic and scatters around its target, so
#' it is reported with a bootstrap confidence interval over test rows. The
#' check fails only when the whole interval sits below `1 - alpha - tolerance`,
#' and is `"weak"` when the interval straddles that line.
#'
#' The interval reflects sampling noise in the *test* set only. The
#' calibration quantile `q` is treated as fixed, so the interval understates
#' total uncertainty when the calibration set is small.
#' @return An `attest_check`.
#' @family conformal checks
#' @examples
#' conformal_split()
#' # 95% target coverage
#' conformal_split(alpha = 0.05)
#' @export
conformal_split <- function(alpha = 0.1, tolerance = 0.03, n_boot = 1000,
                            weighted = FALSE) {
  new_check("conformal_split", stage = "post", run = function(ctx) {
    scores <- conformal_scores(ctx$engine, ctx$model, ctx$calib, ctx$outcome, ctx$task)
    n <- length(scores)
    k <- ceiling((n + 1) * (1 - alpha))
    q <- if (k > n) Inf else sort(scores)[k]
    test_scores <- conformal_scores(ctx$engine, ctx$model, ctx$test, ctx$outcome, ctx$task)
    covered <- test_scores <= q
    cov <- mean(covered)
    ci <- attest_boot(function(i) mean(covered[i]), length(covered), n_boot)
    evidence <- list(
      q = q, alpha = alpha, n_calib = n, coverage_ci = ci,
      curve = coverage_curve(scores, test_scores)
    )
    if (isTRUE(weighted)) {
      # Reweighting at prediction time needs the calibration scores and the
      # covariates they came from, not just the quantile they produced.
      evidence$weighted <- TRUE
      evidence$calib_scores <- scores
      evidence$calib_x <- ctx$calib[, ctx$features, drop = FALSE]
    }
    attest_result(
      "conformal_split",
      attest_verdict(cov, ci, 1 - alpha - tolerance, "at_least"),
      statistic = cov, threshold = 1 - alpha, ci = ci,
      message = sprintf(
        "empirical coverage %.3f%s (target %.3f)%s",
        cov, fmt_ci(ci), 1 - alpha,
        if (isTRUE(weighted)) ", reweighted at predict time" else ""
      ),
      evidence = evidence
    )
  })
}

conformal_scores <- function(engine, model, data, outcome, task) {
  if (task == "classification") {
    p <- engine_predict(engine, model, data, type = "prob")
    y <- as.integer(data[[outcome]]) == 2L
    ifelse(y, 1 - p, p)
  } else if (task == "multiclass") {
    # The same score as the binary case, one minus the probability given to the
    # true class, read from the column for that class.
    p <- engine_predict(engine, model, data, type = "prob_matrix")
    idx <- as.integer(data[[outcome]])
    1 - p[cbind(seq_len(nrow(p)), idx)]
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
#' @param n_boot Replicates used at prediction time to calibrate the flag
#'   against the null distribution of PSI at the incoming batch size. `0`
#'   disables the calibration and compares against `threshold` alone.
#' @param conf Family-wise confidence for the null calibration. The per-feature
#'   quantile is Bonferroni-adjusted by the number of features, so `0.95` means
#'   roughly a 5% chance that an unshifted *batch* raises any flag, rather than
#'   5% per feature.
#' @details
#' PSI is biased upward in small batches. With the default ten bins, a batch of
#' 50 rows drawn from the *training distribution itself* has a median PSI of
#' about 0.2 -- the conventional flag threshold -- so a fixed threshold flags
#' roughly half of all healthy small batches.
#'
#' Rather than compare against a fixed line, this check simulates the null at
#' prediction time: batches of the observed size are drawn from the stored
#' training frequencies, and a feature is flagged only when its PSI exceeds
#' both `threshold` and the upper tail of that null. A flag therefore
#' means "more movement than this batch size produces by chance, and larger
#' than the effect size we care about".
#'
#' Note the contrast with [calib_ece()] and [conformal_split()], which bootstrap
#' *their own estimate* and compare the interval to an absolute target. That
#' works there because those estimators are roughly unbiased for a fixed
#' quantity. It does not work for PSI, whose noise floor depends on the batch
#' size, so the null is simulated instead of the estimate resampled.
#'
#' Sampling from the baseline multinomial costs `O(n_boot * bins)` and is
#' independent of batch size, so the calibration does not scale with the data
#' being predicted.
#'
#' The two bars serve different purposes and the larger one governs. In small
#' batches the simulated null dominates and suppresses noise; in large batches
#' the null falls near zero and `threshold` dominates, acting as an effect-size
#' floor. A consequence is that a real but subtle shift is not flagged however
#' many rows you have, because `threshold` declares it too small to matter. If
#' you predict in large batches and want subtle movement reported, lower
#' `threshold` -- the null calibration will still hold the false-positive rate.
#' @return An `attest_check`.
#' @family shift checks
#' @examples
#' shift_monitor()
#' # skip the null calibration on a latency-sensitive prediction path
#' shift_monitor(n_boot = 0)
#' @export
shift_monitor <- function(threshold = 0.2, bins = 10, support_tol = 0.05,
                          min_batch = 50, n_boot = 500, conf = 0.95) {
  new_check("shift_monitor", stage = "post", blocking = FALSE, run = function(ctx) {
    baseline <- lapply(ctx$features, function(f) {
      x <- ctx$train[[f]]
      if (is.numeric(x)) {
        br <- unique(stats::quantile(
          x,
          probs = seq(0, 1, length.out = bins + 1), na.rm = TRUE
        ))
        if (length(br) < 2) br <- c(min(x), max(x) + 1e-8)
        freq <- as.numeric(table(cut(x, br, include.lowest = TRUE))) / length(x)
        rng <- range(x, na.rm = TRUE)
        pad <- support_tol * diff(rng)
        list(
          type = "numeric", breaks = br, freq = freq,
          support = c(rng[1] - pad, rng[2] + pad)
        )
      } else {
        lv <- levels(as.factor(x))
        freq <- as.numeric(table(factor(x, levels = lv))) / length(x)
        list(type = "categorical", levels = lv, freq = freq)
      }
    })
    names(baseline) <- ctx$features
    attest_result("shift_monitor", "info",
      threshold = threshold,
      message = "baseline stored",
      evidence = list(
        baseline = baseline, threshold = threshold,
        min_batch = min_batch, n_boot = n_boot,
        conf = conf,
        mahalanobis = mahalanobis_baseline(ctx$train, ctx$features)
      )
    )
  })
}

#' Shift check: classifier two-sample test on the prediction batch
#'
#' Stores a reference sample of the training rows. At prediction time a
#' classifier is asked to tell that reference from the incoming batch, using
#' held-out scores; an AUC near 0.5 means the two are indistinguishable. See
#' [attest_c2st()] for the mechanics.
#'
#' @details
#' This complements [shift_monitor()] rather than replacing it. PSI is computed
#' per feature on binned marginals, so it cannot see a change in the
#' relationship *between* features. Two samples with identical marginals but
#' opposite correlation produce no PSI signal at all, while the classifier
#' separates them easily. Conversely PSI is cheaper, needs no reference sample
#' stored in the certificate, and says which feature moved.
#'
#' A batch is flagged only when the test is both significant at `alpha` and the
#' held-out AUC reaches `auc_min`. The second bar matters because a large enough
#' batch makes an arbitrarily small difference significant, and a shift too
#' small to separate the samples is rarely a shift worth acting on.
#'
#' @param auc_min Minimum held-out AUC before a batch is flagged, an effect
#'   size floor.
#' @param alpha Significance level for the test.
#' @param max_ref Maximum number of training rows stored as the reference
#'   sample. Larger gives more power and a larger certificate.
#' @param min_batch Minimum incoming rows before the test is attempted.
#' @param interactions Passed to [attest_c2st()]; keep `TRUE` to detect changes
#'   in the dependence between features.
#' @return An `attest_check`.
#' @family shift checks
#' @examples
#' shift_c2st()
#' # demand a clearer separation before flagging
#' shift_c2st(auc_min = 0.7)
#' @export
shift_c2st <- function(auc_min = 0.6, alpha = 0.05, max_ref = 2000,
                       min_batch = 50, interactions = TRUE) {
  new_check("shift_c2st", stage = "post", blocking = FALSE, run = function(ctx) {
    n <- nrow(ctx$train)
    take <- if (n > max_ref) sample.int(n, max_ref) else seq_len(n)
    attest_result("shift_c2st", "info",
      threshold = auc_min,
      message = sprintf("reference sample stored (%d rows)", length(take)),
      evidence = list(
        reference = ctx$train[take, ctx$features, drop = FALSE],
        auc_min = auc_min, alpha = alpha, min_batch = min_batch,
        interactions = interactions
      )
    )
  })
}

# Single-feature predictive strength for a multiclass outcome. A binary outcome
# gets a one-variable logistic fit; with more than two classes that is not
# available without another dependency, so the feature is binned and each bin
# predicts its majority class. A feature that determines the outcome -- an
# identifier, a field recorded after the label -- reaches an accuracy of one
# either way, which is what the check is looking for.
stump_hits <- function(x, y, bins = 10) {
  g <- if (is.numeric(x)) {
    br <- unique(stats::quantile(x, seq(0, 1, length.out = bins + 1), na.rm = TRUE))
    if (length(br) < 2) {
      return(NULL)
    }
    cut(x, br, include.lowest = TRUE)
  } else {
    factor(x)
  }
  tab <- table(g, y)
  if (!nrow(tab) || !ncol(tab)) {
    return(NULL)
  }
  best <- colnames(tab)[max.col(tab, ties.method = "first")]
  names(best) <- rownames(tab)
  hit <- as.character(y) == best[as.character(g)]
  hit[is.na(hit)] <- FALSE
  as.numeric(hit)
}

psi <- function(expected, actual, eps = 1e-4) {
  e <- pmax(expected, eps)
  a <- pmax(actual, eps)
  sum((a - e) * log(a / e))
}

# PSI is biased upward in small batches: with 10 bins and 50 rows its median
# under no shift at all is about 0.2, the conventional flag threshold. A
# bootstrap of the observed batch cannot correct this, because it resamples a
# distribution that already carries the bias. Instead we simulate the null --
# draw batches of the same size from the training frequencies and read off a
# high quantile -- which gives the PSI a batch of this size produces when
# nothing has changed. Sampling counts from the baseline multinomial costs
# O(n_boot * bins) and is independent of batch size.
psi_null_quantile <- function(freq, n, n_boot = 200, conf = 0.95) {
  if (n_boot < 2 || n < 1 || anyNA(freq)) {
    return(NA_real_)
  }
  counts <- stats::rmultinom(n_boot, size = n, prob = freq)
  vals <- apply(counts, 2, function(cc) psi(freq, cc / n))
  vals <- vals[is.finite(vals)]
  if (!length(vals)) {
    return(NA_real_)
  }
  unname(stats::quantile(vals, conf, names = FALSE))
}
