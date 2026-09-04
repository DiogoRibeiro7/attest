#' Predict with validity status
#'
#' Returns an `attested_prediction`: a tibble with `.pred`, an interval
#' (`.lower`/`.upper` for regression, `.set` for classification), a
#' `.status` of `"valid"`, `"flagged"` or `"refused"`, a row-level `.shift`
#' score and a `.reason`. Refused rows have `NA` predictions unless
#' `enforce = FALSE`.
#'
#' @details
#' `.shift` is the row's Mahalanobis position within the joint training
#' distribution, on a chi-square probability scale: 0.5 is a typical row and
#' 0.99 means further from the centre than 99% of the training data. Because it
#' uses the joint structure it catches a row that is unremarkable on every
#' feature taken alone but implausible in combination, which a per-feature tail
#' measure cannot. It falls back to the share of features in the tails when the
#' model has no numeric features to form a covariance from.
#'
#' When the model was fitted with `conformal_split(weighted = TRUE)` the
#' interval is not fixed. Calibration scores are reweighted by an estimated
#' covariate density ratio between the calibration set and this batch, so each
#' row gets its own quantile and intervals widen on drifted input. The estimated
#' ratio is returned in a `.weight` column.
#'
#' `.status` keeps its meaning throughout: `"flagged"` still reports that the
#' batch moved, not that the interval changed. A row whose reweighted quantile
#' is infinite -- the calibration set holds no comparable evidence -- is
#' refused, with reason `"no conformal evidence after reweighting"`.
#'
#' @param object An `attested_model`.
#' @param newdata Data to predict on.
#' @param enforce If `FALSE`, refused rows still receive predictions (status is
#'   kept). Overriding the contract is recorded in the returned object's
#'   `"enforced"` attribute.
#' @param ... Unused.
#' @return A tibble of class `attested_prediction`.
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' predict(m, d[1:3, ])
#' # a row outside the certified support is refused
#' nd <- d[1:2, ]
#' nd$x1[1] <- 50
#' predict(m, nd)
#' @export
predict.attested_model <- function(object, newdata, enforce = TRUE, ...) {
  newdata <- as.data.frame(newdata)
  missing <- setdiff(object$features, names(newdata))
  if (length(missing)) {
    rlang::abort(sprintf(
      "missing features: %s",
      paste(missing, collapse = ", ")
    ))
  }
  if (!is_sealed(object)) {
    rlang::abort(paste(
      "model is not sealed: certificate is invalid or the model was",
      "modified after certification"
    ))
  }
  n <- nrow(newdata)

  sh <- shift_eval(object$shift, newdata, object$features)
  status <- rep("valid", n)
  reason <- rep(NA_character_, n)
  if (length(sh$batch_flagged)) {
    status[] <- "flagged"
    bar <- max(sh$effective_threshold[sh$batch_flagged], na.rm = TRUE)
    reason[] <- sprintf(
      "PSI %.2f > %.2f on %s",
      max(sh$batch_psi[sh$batch_flagged]), bar,
      paste(sh$batch_flagged, collapse = ", ")
    )
  }
  c2 <- c2st_eval(object$c2st, newdata, object$features)
  if (isTRUE(c2$flagged)) {
    status[] <- "flagged"
    note <- sprintf("C2ST auc %.2f (p %.3g)", c2$auc, c2$p_value)
    reason[] <- ifelse(is.na(reason), note, paste(reason, note, sep = "; "))
  }
  status[sh$refused] <- "refused"
  reason[sh$refused] <- sh$refuse_reason[sh$refused]

  keep <- if (enforce) status != "refused" else rep(TRUE, n)
  pred <- rep(NA_real_, n)
  if (any(keep)) {
    type <- if (object$task == "classification") "prob" else "numeric"
    pred[keep] <- tryCatch(
      engine_predict(
        object$engine, object$model,
        newdata[keep, , drop = FALSE], type
      ),
      error = function(e) {
        if (enforce) rlang::abort(conditionMessage(e), parent = e)
        rlang::warn(c(
          "engine could not predict on unenforced rows; returning NA",
          conditionMessage(e)
        ))
        NA_real_
      }
    )
  }

  wq <- weighted_q(object$conformal, newdata, object$features)
  q <- wq$q
  # An infinite quantile means the calibration set carries no usable evidence
  # for that row, so there is no interval to return: refuse it like any other
  # row outside the certified support.
  if (any(is.infinite(q))) {
    gone <- is.infinite(q) & status != "refused"
    status[gone] <- "refused"
    reason[gone] <- "no conformal evidence after reweighting"
    if (enforce) pred[gone] <- NA_real_
  }

  out <- tibble::tibble(.pred = pred)
  if (object$task == "regression") {
    out$.lower <- pred - q
    out$.upper <- pred + q
  } else {
    lv <- object$levels
    out$.set <- vapply(seq_along(pred), function(i) {
      p <- pred[i]
      if (is.na(p)) {
        return(NA_character_)
      }
      qi <- q[i]
      s <- c(if (p <= qi) lv[1], if (1 - p <= qi) lv[2])
      if (length(s) == 0) "{}" else paste0("{", paste(s, collapse = ","), "}")
    }, character(1))
  }
  out$.status <- status
  out$.shift <- sh$row_score
  if (!is.null(wq$weight)) out$.weight <- wq$weight
  out$.reason <- reason
  structure(out,
    class = c("attested_prediction", class(out)),
    certificate_id = object$certificate$id, enforced = enforce
  )
}

shift_eval <- function(shift, newdata, features) {
  n <- nrow(newdata)
  if (is.null(shift)) {
    return(list(
      batch_flagged = character(0), refused = rep(FALSE, n),
      refuse_reason = rep(NA_character_, n), row_score = rep(0, n), threshold = NA
    ))
  }
  base <- shift$baseline
  n_boot <- shift$n_boot %||% 0
  # Bonferroni across features: the batch is flagged if any feature fires, so
  # the per-feature quantile must be tightened to hold the family-wise rate.
  conf_f <- 1 - (1 - (shift$conf %||% 0.95)) / max(1, length(features))
  out_of_support <- matrix(FALSE, n, length(features), dimnames = list(NULL, features))
  central <- matrix(FALSE, n, length(features))
  batch_psi <- numeric(length(features))
  names(batch_psi) <- features
  psi_null <- rep(NA_real_, length(features))
  names(psi_null) <- features
  for (j in seq_along(features)) {
    f <- features[j]
    b <- base[[f]]
    x <- newdata[[f]]
    if (b$type == "numeric") {
      out_of_support[, j] <- !is.na(x) & (x < b$support[1] | x > b$support[2])
      br <- b$breaks
      central[, j] <- !is.na(x) & (x < br[2] | x > br[length(br) - 1])
      if (n >= shift$min_batch) {
        act <- as.numeric(table(cut(x, br, include.lowest = TRUE))) / sum(!is.na(x))
        batch_psi[j] <- psi(b$freq, act)
        psi_null[j] <- psi_null_quantile(b$freq, n, n_boot, conf_f)
      }
    } else {
      xf <- as.character(x)
      out_of_support[, j] <- !is.na(xf) & !(xf %in% b$levels)
      rare <- b$levels[b$freq < 0.05]
      central[, j] <- xf %in% rare
      if (n >= shift$min_batch) {
        act <- as.numeric(table(factor(xf, levels = b$levels))) / sum(!is.na(xf))
        batch_psi[j] <- psi(b$freq, act)
        psi_null[j] <- psi_null_quantile(b$freq, n, n_boot, conf_f)
      }
    }
  }
  # A feature is flagged only when its PSI exceeds both the effect-size
  # threshold and what a batch of this size produces under no shift at all.
  # Without the second condition, small batches flag constantly: see
  # psi_null_quantile().
  effective <- pmax(shift$threshold, ifelse(is.na(psi_null), -Inf, psi_null))
  refused <- rowSums(out_of_support) > 0
  refuse_reason <- rep(NA_character_, n)
  if (any(refused)) {
    refuse_reason[refused] <- vapply(which(refused), function(i) {
      sprintf(
        "outside training support: %s",
        paste(features[out_of_support[i, ]], collapse = ", ")
      )
    }, character(1))
  }
  flagged <- names(batch_psi)[batch_psi > effective]
  # Prefer the Mahalanobis position within the joint training distribution;
  # the per-feature tail share is only a fallback when there is nothing
  # numeric to build a covariance from.
  row_score <- mahalanobis_score(shift$mahalanobis, newdata)
  if (is.null(row_score)) row_score <- rowMeans(central)
  list(
    batch_flagged = flagged,
    refused = refused, refuse_reason = refuse_reason,
    row_score = row_score, threshold = shift$threshold,
    batch_psi = batch_psi, psi_null = psi_null,
    effective_threshold = stats::setNames(effective, features)
  )
}

#' @export
print.attested_prediction <- function(x, ...) {
  # Subsetting keeps the class but may drop `.status`, so the header is only
  # printed when the column it summarises is still present.
  if (".status" %in% names(x)) {
    cert <- attr(x, "certificate_id")
    note <- if (isTRUE(attr(x, "enforced"))) "" else " (NOT enforced)"
    cli::cli_text(
      "# attested_prediction: {nrow(x)} row{?s}, certificate {cert}{note}"
    )
    tab <- table(factor(x$.status, levels = c("valid", "flagged", "refused")))
    cli::cli_text("{paste(names(tab), tab, sep = ': ', collapse = ' | ')}")
  }
  NextMethod()
}

# ---- Report ----------------------------------------------------------------

#' Render a model card from the certificate
#'
#' The report is generated entirely from the `attested_model` object, so it
#' cannot drift from the model.
#'
#' @param x An `attested_model`.
#' @param file Optional path; if `NULL` the Markdown text is returned.
#' @return Invisibly, the Markdown text (a character vector of lines).
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' cat(report(m)[1:8], sep = "\n")
#' @export
report <- function(x, file = NULL) {
  stopifnot(inherits(x, "attested_model"))
  ce <- x$certificate
  lines <- c(
    sprintf("# Model card: %s (%s)", ce$outcome, ce$task),
    "",
    sprintf(
      "Certificate `%s`, issued %s UTC, status **%s** (on_fail = `%s`), attest %s.",
      ce$id, ce$issued, ce$status, ce$on_fail, ce$attest_version
    ),
    "",
    sprintf("- Engine: `%s`", ce$engine),
    sprintf(
      "- Split: `%s` -- train %d / calib %d / test %d",
      ce$split, ce$n["train"], ce$n["calib"], ce$n["test"]
    ),
    sprintf(
      "- Features (%d): %s",
      length(ce$features), paste0("`", ce$features, "`", collapse = ", ")
    ),
    sprintf(
      "- Hashes: data `%s`, model `%s`",
      substr(ce$hashes$data, 1, 12), substr(ce$hashes$model, 1, 12)
    ),
    "",
    "## Checks",
    "",
    "| check | status | statistic | 95% CI | threshold | detail |",
    "|---|---|---|---|---|---|"
  )
  for (r in ce$results) {
    ci <- r$ci
    ci_txt <- if (is.null(ci) || length(ci) != 2 || anyNA(ci)) {
      ""
    } else {
      sprintf("[%s, %s]", fmt_num(ci[1]), fmt_num(ci[2]))
    }
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s | %s | %s |", r$id,
      switch(r$status,
        fail = "**FAIL**",
        weak = "_weak_",
        r$status
      ),
      fmt_num(r$statistic), ci_txt,
      fmt_num(r$threshold), r$message
    ))
  }
  if (!is.null(ce$waivers)) {
    lines <- c(
      lines, "", "## Waivers", "",
      sprintf(
        "> **%s** waived. Reason given: \"%s\"",
        paste(ce$waivers$ids, collapse = ", "), ce$waivers$reason
      )
    )
  }
  if (!is.null(x$conformal)) {
    cov_ci <- x$conformal$coverage_ci
    cov_txt <- if (is.null(cov_ci) || anyNA(cov_ci)) {
      ""
    } else {
      sprintf(
        paste(
          " Measured coverage interval [%s, %s] reflects test-set sampling",
          "noise only; the calibration quantile is treated as fixed."
        ),
        fmt_num(cov_ci[1]), fmt_num(cov_ci[2])
      )
    }
    lines <- c(
      lines, "", "## Prediction guarantee", "",
      sprintf(
        paste(
          "Split conformal, alpha = %.2f, calibrated on %d rows,",
          "quantile %s. Coverage is marginal (on average over",
          "exchangeable data), not conditional on any row.%s"
        ),
        x$conformal$alpha, x$conformal$n_calib, fmt_num(x$conformal$q), cov_txt
      )
    )
  }
  lines <- c(
    lines, "", "## Refusal policy", "",
    paste(
      "Rows with any numeric feature outside the training support (widened",
      "by tolerance) or an unseen categorical level are refused. Batches",
      "with feature PSI above the threshold are flagged."
    )
  )
  if (!is.null(file)) writeLines(lines, file)
  invisible(lines)
}

fmt_num <- function(v) {
  if (is.na(v)) {
    ""
  } else if (is.infinite(v)) {
    "Inf"
  } else {
    formatC(v, digits = 3, format = "f")
  }
}
