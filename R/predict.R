#' Predict with validity status
#'
#' Returns an `attested_prediction`: a tibble with `.pred`, an interval
#' (`.lower`/`.upper` for regression, `.set` for classification), a
#' `.status` of `"valid"`, `"flagged"` or `"refused"`, a row-level `.shift`
#' score (share of features outside the central training range) and a
#' `.reason`. Refused rows have `NA` predictions unless `enforce = FALSE`.
#'
#' @param object An `attested_model`.
#' @param newdata Data to predict on.
#' @param enforce If `FALSE`, refused rows still receive predictions (status is
#'   kept). Overriding the contract is recorded in the returned object's
#'   `"enforced"` attribute.
#' @param ... Unused.
#' @return A tibble of class `attested_prediction`.
#' @export
predict.attested_model <- function(object, newdata, enforce = TRUE, ...) {
  newdata <- as.data.frame(newdata)
  missing <- setdiff(object$features, names(newdata))
  if (length(missing)) rlang::abort(sprintf("missing features: %s", paste(missing, collapse = ", ")))
  if (!is_sealed(object)) {
    rlang::abort("model is not sealed: certificate is invalid or the model was modified after certification")
  }
  n <- nrow(newdata)

  sh <- shift_eval(object$shift, newdata, object$features)
  status <- rep("valid", n)
  reason <- rep(NA_character_, n)
  if (length(sh$batch_flagged)) {
    status[] <- "flagged"
    reason[] <- sprintf("PSI > %.2f on %s", sh$threshold, paste(sh$batch_flagged, collapse = ", "))
  }
  status[sh$refused] <- "refused"
  reason[sh$refused] <- sh$refuse_reason[sh$refused]

  keep <- if (enforce) status != "refused" else rep(TRUE, n)
  pred <- rep(NA_real_, n)
  if (any(keep)) {
    type <- if (object$task == "classification") "prob" else "numeric"
    pred[keep] <- tryCatch(
      engine_predict(object$engine, object$model, newdata[keep, , drop = FALSE], type),
      error = function(e) {
        if (enforce) rlang::abort(conditionMessage(e), parent = e)
        rlang::warn(c("engine could not predict on unenforced rows; returning NA", conditionMessage(e)))
        NA_real_
      })
  }

  out <- tibble::tibble(.pred = pred)
  q <- object$conformal$q
  if (object$task == "regression") {
    out$.lower <- pred - q
    out$.upper <- pred + q
  } else {
    lv <- object$levels
    out$.set <- ifelse(is.na(pred), NA_character_, vapply(pred, function(p) {
      if (is.na(p)) return(NA_character_)
      s <- c(if (p <= q) lv[1], if (1 - p <= q) lv[2])
      if (length(s) == 0) "{}" else paste0("{", paste(s, collapse = ","), "}")
    }, character(1)))
  }
  out$.status <- status
  out$.shift <- sh$row_score
  out$.reason <- reason
  structure(out, class = c("attested_prediction", class(out)),
            certificate_id = object$certificate$id, enforced = enforce)
}

shift_eval <- function(shift, newdata, features) {
  n <- nrow(newdata)
  if (is.null(shift)) {
    return(list(batch_flagged = character(0), refused = rep(FALSE, n),
                refuse_reason = rep(NA_character_, n), row_score = rep(0, n), threshold = NA))
  }
  base <- shift$baseline
  out_of_support <- matrix(FALSE, n, length(features), dimnames = list(NULL, features))
  central <- matrix(FALSE, n, length(features))
  batch_psi <- numeric(length(features)); names(batch_psi) <- features
  for (j in seq_along(features)) {
    f <- features[j]; b <- base[[f]]; x <- newdata[[f]]
    if (b$type == "numeric") {
      out_of_support[, j] <- !is.na(x) & (x < b$support[1] | x > b$support[2])
      br <- b$breaks
      central[, j] <- !is.na(x) & (x < br[2] | x > br[length(br) - 1])
      if (n >= shift$min_batch) {
        act <- as.numeric(table(cut(x, br, include.lowest = TRUE))) / sum(!is.na(x))
        batch_psi[j] <- psi(b$freq, act)
      }
    } else {
      xf <- as.character(x)
      out_of_support[, j] <- !is.na(xf) & !(xf %in% b$levels)
      rare <- b$levels[b$freq < 0.05]
      central[, j] <- xf %in% rare
      if (n >= shift$min_batch) {
        act <- as.numeric(table(factor(xf, levels = b$levels))) / sum(!is.na(xf))
        batch_psi[j] <- psi(b$freq, act)
      }
    }
  }
  refused <- rowSums(out_of_support) > 0
  refuse_reason <- rep(NA_character_, n)
  if (any(refused)) {
    refuse_reason[refused] <- vapply(which(refused), function(i) {
      sprintf("outside training support: %s", paste(features[out_of_support[i, ]], collapse = ", "))
    }, character(1))
  }
  list(batch_flagged = names(batch_psi)[batch_psi > shift$threshold],
       refused = refused, refuse_reason = refuse_reason,
       row_score = rowMeans(central), threshold = shift$threshold, batch_psi = batch_psi)
}

#' @export
print.attested_prediction <- function(x, ...) {
  cli::cli_text("# attested_prediction: {nrow(x)} row{?s}, certificate {attr(x, 'certificate_id')}{if (!isTRUE(attr(x, 'enforced'))) ' (NOT enforced)' else ''}")
  tab <- table(factor(x$.status, levels = c("valid", "flagged", "refused")))
  cli::cli_text("{paste(names(tab), tab, sep = ': ', collapse = ' | ')}")
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
#' @export
report <- function(x, file = NULL) {
  stopifnot(inherits(x, "attested_model"))
  ce <- x$certificate
  lines <- c(
    sprintf("# Model card: %s (%s)", ce$outcome, ce$task),
    "",
    sprintf("Certificate `%s`, issued %s UTC, status **%s** (on_fail = `%s`), attest %s.",
            ce$id, ce$issued, ce$status, ce$on_fail, ce$attest_version),
    "",
    sprintf("- Engine: `%s`", ce$engine),
    sprintf("- Split: `%s` -- train %d / calib %d / test %d", ce$split, ce$n["train"], ce$n["calib"], ce$n["test"]),
    sprintf("- Features (%d): %s", length(ce$features), paste0("`", ce$features, "`", collapse = ", ")),
    sprintf("- Hashes: data `%s`, model `%s`", substr(ce$hashes$data, 1, 12), substr(ce$hashes$model, 1, 12)),
    "",
    "## Checks",
    "",
    "| check | status | statistic | threshold | detail |",
    "|---|---|---|---|---|"
  )
  for (r in ce$results) {
    lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", r$id,
                              if (r$status == "fail") "**FAIL**" else r$status,
                              fmt_num(r$statistic), fmt_num(r$threshold), r$message))
  }
  if (!is.null(ce$waivers)) {
    lines <- c(lines, "", "## Waivers", "",
               sprintf("> **%s** waived. Reason given: \"%s\"", paste(ce$waivers$ids, collapse = ", "), ce$waivers$reason))
  }
  if (!is.null(x$conformal)) {
    lines <- c(lines, "", "## Prediction guarantee", "",
               sprintf("Split conformal, alpha = %.2f, calibrated on %d rows, quantile %s. Coverage is marginal (on average over exchangeable data), not conditional on any row.",
                       x$conformal$alpha, x$conformal$n_calib, fmt_num(x$conformal$q)))
  }
  lines <- c(lines, "", "## Refusal policy", "",
             "Rows with any numeric feature outside the training support (widened by tolerance) or an unseen categorical level are refused. Batches with feature PSI above the threshold are flagged.")
  if (!is.null(file)) writeLines(lines, file)
  invisible(lines)
}

fmt_num <- function(v) if (is.na(v)) "" else if (is.infinite(v)) "Inf" else formatC(v, digits = 3, format = "f")
