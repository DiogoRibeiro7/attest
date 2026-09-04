#' Classifier two-sample test
#'
#' Tests whether two samples come from the same distribution by asking how well
#' a classifier can tell them apart. An AUC near 0.5 means the samples are
#' indistinguishable; an AUC near 1 means a model can separate them, which is
#' what distribution shift looks like.
#'
#' Scores are produced by cross-fitting: the pooled data is split in two, each
#' half is scored by a model fitted on the other, and the AUC is computed on
#' those held-out scores. This matters, because an in-sample AUC is optimistic
#' -- a flexible model can separate two identical samples if it is allowed to
#' fit and score the same rows -- and would report shift where there is none.
#'
#' Because the scores are held out, under the null the labels are independent
#' of them and the AUC is a Mann-Whitney statistic, so the p-value uses that
#' standard normal approximation rather than needing a permutation loop.
#'
#' @param reference Data frame of reference (training-time) rows.
#' @param new Data frame of incoming rows.
#' @param features Columns to compare.
#' @param interactions If `TRUE` and the feature count is small, the classifier
#'   gets squared terms and pairwise interactions. Without them a linear
#'   classifier only sees shifts in means, and is blind to a change in the
#'   dependence between features that leaves every marginal intact -- exactly
#'   the case a per-feature statistic such as PSI also misses.
#' @param max_terms Maximum number of features for which `interactions` is
#'   honoured, keeping the fit affordable.
#' @return A list with `auc` (held-out), `p_value` (one-sided, against the null
#'   of no shift), `n_ref` and `n_new`.
#' @examples
#' set.seed(1)
#' a <- data.frame(x = rnorm(300), z = rnorm(300))
#' same <- data.frame(x = rnorm(300), z = rnorm(300))
#' shifted <- data.frame(x = rnorm(300, 1), z = rnorm(300))
#' round(attest_c2st(a, same, c("x", "z"))$p_value, 3)
#' round(attest_c2st(a, shifted, c("x", "z"))$p_value, 3)
#' @export
attest_c2st <- function(reference, new, features, interactions = TRUE,
                        max_terms = 8) {
  reference <- as.data.frame(reference)[, features, drop = FALSE]
  new <- as.data.frame(new)[, features, drop = FALSE]
  n_r <- nrow(reference)
  n_n <- nrow(new)
  flat <- list(auc = 0.5, p_value = 1, n_ref = n_r, n_new = n_n)
  if (n_r < 20 || n_n < 20) {
    return(flat)
  }

  pooled <- rbind(reference, new)
  for (f in features) {
    if (!is.numeric(pooled[[f]])) {
      pooled[[f]] <- factor(pooled[[f]])
      if (nlevels(pooled[[f]]) < 2) pooled[[f]] <- NULL
    }
  }
  usable <- intersect(features, names(pooled))
  if (!length(usable)) {
    return(flat)
  }
  y <- c(rep(0L, n_r), rep(1L, n_n))

  rhs <- paste(usable, collapse = " + ")
  if (isTRUE(interactions) && length(usable) <= max_terms) {
    num <- usable[vapply(pooled[usable], is.numeric, logical(1))]
    sq <- if (length(num)) paste0("I(", num, "^2)") else character(0)
    pair <- if (length(usable) > 1) paste0("(", rhs, ")^2") else rhs
    rhs <- paste(c(pair, sq), collapse = " + ")
  }
  fml <- stats::as.formula(paste(".c2st_y ~", rhs))

  # Cross-fitting: each row is scored by a model that never saw it.
  fold <- sample(rep_len(1:2, length(y)))
  scores <- rep(NA_real_, length(y))
  for (k in 1:2) {
    tr <- fold != k
    dat <- pooled[tr, , drop = FALSE]
    dat$.c2st_y <- y[tr]
    if (length(unique(dat$.c2st_y)) < 2) next
    fit <- tryCatch(
      suppressWarnings(stats::glm(fml, data = dat, family = stats::binomial())),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    scores[!tr] <- tryCatch(
      as.numeric(stats::predict(fit, newdata = pooled[!tr, , drop = FALSE])),
      error = function(e) NA_real_
    )
  }
  ok <- !is.na(scores)
  if (sum(ok & y == 1L) < 5 || sum(ok & y == 0L) < 5) {
    return(flat)
  }

  auc <- auc_stat(y[ok], scores[ok])
  n1 <- sum(ok & y == 1L)
  n0 <- sum(ok & y == 0L)
  se <- sqrt((n1 + n0 + 1) / (12 * n1 * n0))
  p <- stats::pnorm((auc - 0.5) / se, lower.tail = FALSE)
  list(auc = auc, p_value = p, n_ref = n_r, n_new = n_n)
}

# Run the stored classifier two-sample test against an incoming batch. A batch
# is flagged only when the test is significant *and* the separation reaches the
# effect-size floor, mirroring how the PSI monitor combines its simulated null
# with a threshold.
c2st_eval <- function(c2st, newdata, features) {
  none <- list(flagged = FALSE, auc = NA_real_, p_value = NA_real_)
  if (is.null(c2st) || is.null(c2st$reference)) {
    return(none)
  }
  if (nrow(newdata) < (c2st$min_batch %||% 50)) {
    return(none)
  }
  if (!all(features %in% names(newdata))) {
    return(none)
  }
  r <- attest_c2st(
    c2st$reference, newdata, features,
    interactions = isTRUE(c2st$interactions)
  )
  r$flagged <- isFALSE(is.na(r$p_value)) &&
    r$p_value < (c2st$alpha %||% 0.05) &&
    r$auc >= (c2st$auc_min %||% 0.6)
  r
}

# Mahalanobis position of each row within the training distribution, expressed
# as a chi-square probability: 0.5 is a typical row, 0.99 means further from the
# centre than 99% of training data. Unlike a per-feature tail share this uses
# the joint structure, so a row that is unremarkable on every feature taken
# alone but implausible in combination still scores high.
mahalanobis_baseline <- function(x, features) {
  num <- features[vapply(x[features], is.numeric, logical(1))]
  if (!length(num)) {
    return(NULL)
  }
  m <- as.matrix(x[, num, drop = FALSE])
  keep <- stats::complete.cases(m)
  m <- m[keep, , drop = FALSE]
  if (nrow(m) <= length(num) + 1) {
    return(NULL)
  }
  centre <- colMeans(m)
  covm <- stats::cov(m)
  # Ridge the covariance so collinear or constant features stay invertible.
  ridge <- diag(length(num)) * max(1e-8, mean(diag(covm)) * 1e-6)
  prec <- tryCatch(solve(covm + ridge), error = function(e) NULL)
  if (is.null(prec)) {
    return(NULL)
  }
  list(features = num, centre = centre, precision = prec, df = length(num))
}

mahalanobis_score <- function(baseline, newdata) {
  if (is.null(baseline)) {
    return(NULL)
  }
  f <- baseline$features
  if (!all(f %in% names(newdata))) {
    return(NULL)
  }
  m <- as.matrix(newdata[, f, drop = FALSE])
  storage.mode(m) <- "double"
  d <- sweep(m, 2, baseline$centre, "-")
  d2 <- rowSums((d %*% baseline$precision) * d)
  d2[!is.finite(d2)] <- NA_real_
  stats::pchisq(d2, df = baseline$df)
}
