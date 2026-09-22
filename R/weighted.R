#' Estimate a covariate density ratio between calibration and new data
#'
#' Fits a probabilistic classifier separating the calibration rows from the
#' incoming rows and converts its predictions into a likelihood ratio
#' \eqn{w(x) = \mathrm{d}Q_X / \mathrm{d}P_X(x)}, estimated as the odds
#' \eqn{p(x) / (1 - p(x))} where \eqn{p} is the probability a row came from the
#' new batch. This is the "classifier two-sample" estimator: an AUC near 0.5
#' means the two samples are indistinguishable and every weight is near 1.
#'
#' Only a global constant separates the odds from the true ratio, and that
#' constant cancels in [attest_weighted_quantile()], so no calibration of the
#' scale is required.
#'
#' @param calib_x Data frame of calibration covariates.
#' @param new_x Data frame of incoming covariates, same columns.
#' @param features Character vector of columns to use.
#' @param max_ratio Weights are clipped to `[1 / max_ratio, max_ratio]`. An
#'   unclipped ratio can be enormous when the classifier separates the samples
#'   almost perfectly, which would let a handful of rows dominate the weighted
#'   quantile.
#' @return A list with `calib` and `new`, the weights for each set, and `auc`,
#'   the in-sample area under the curve of the discriminating classifier.
#' @family conformal checks
#' @family shift checks
#' @examples
#' set.seed(1)
#' a <- data.frame(x = rnorm(300))
#' b <- data.frame(x = rnorm(300, 1))
#' w <- attest_density_ratio(a, b, "x")
#' round(w$auc, 2)
#' @export
attest_density_ratio <- function(calib_x, new_x, features, max_ratio = 100) {
  calib_x <- as.data.frame(calib_x)[, features, drop = FALSE]
  new_x <- as.data.frame(new_x)[, features, drop = FALSE]
  n_c <- nrow(calib_x)
  n_n <- nrow(new_x)
  flat <- list(calib = rep(1, n_c), new = rep(1, n_n), auc = 0.5)
  if (n_c < 10 || n_n < 10) {
    return(flat)
  }

  pooled <- rbind(calib_x, new_x)
  # Levels seen in only one sample would make the fit unidentifiable, so
  # categorical columns are reduced to the levels the two samples share.
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
  pooled$.from_new <- c(rep(0L, n_c), rep(1L, n_n))

  fml <- stats::reformulate(usable, response = ".from_new")
  fit <- tryCatch(
    suppressWarnings(stats::glm(fml, data = pooled, family = stats::binomial())),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    return(flat)
  }
  p <- tryCatch(
    as.numeric(stats::predict(fit, type = "response")),
    error = function(e) rep(0.5, nrow(pooled))
  )
  if (anyNA(p)) p[is.na(p)] <- 0.5
  eps <- 1e-6
  p <- pmin(pmax(p, eps), 1 - eps)
  w <- p / (1 - p)
  w <- pmin(pmax(w, 1 / max_ratio), max_ratio)

  list(
    calib = w[seq_len(n_c)],
    new = w[n_c + seq_len(n_n)],
    auc = auc_stat(pooled$.from_new, p)
  )
}

# Resolve the conformal quantile for a batch. Without `weighted = TRUE` on
# conformal_split() this is the single fixed quantile the certificate recorded,
# recycled across rows. With it, the calibration scores are reweighted by an
# estimated covariate density ratio and each row gets its own quantile.
weighted_q <- function(conformal, newdata, features) {
  n <- nrow(newdata)
  fixed <- list(q = rep(conformal$q %||% Inf, n), weight = NULL)
  if (!isTRUE(conformal$weighted) || is.null(conformal$calib_scores)) {
    return(fixed)
  }
  calib_x <- conformal$calib_x
  if (is.null(calib_x) || !all(features %in% names(newdata))) {
    return(fixed)
  }
  w <- attest_density_ratio(calib_x, newdata, features)
  q <- attest_weighted_quantile(
    conformal$calib_scores, w$calib, w$new,
    alpha = conformal$alpha %||% 0.1
  )
  list(q = q, weight = w$new, auc = w$auc)
}

auc_stat <- function(y, p) {
  pos <- p[y == 1L]
  neg <- p[y == 0L]
  if (!length(pos) || !length(neg)) {
    return(0.5)
  }
  r <- rank(c(pos, neg))
  (sum(r[seq_along(pos)]) - length(pos) * (length(pos) + 1) / 2) /
    (length(pos) * length(neg))
}

#' Weighted conformal quantile
#'
#' The quantile of Tibshirani et al. (2019) for conformal prediction under
#' covariate shift. Calibration scores are weighted by their density ratio and
#' augmented with a point mass at infinity carrying the test point's own
#' weight, so a test point unlike anything in the calibration set receives an
#' infinite quantile rather than a falsely narrow one.
#'
#' @param scores Numeric calibration scores.
#' @param w_calib Weights for the calibration scores, same length.
#' @param w_new Weights for the points being predicted, one per row.
#' @param alpha Miscoverage level; the quantile targets `1 - alpha`.
#' @return A numeric vector the length of `w_new`, possibly containing `Inf`.
#' @family conformal checks
#' @details
#' With every weight equal to 1 this reduces exactly to the ordinary split
#' conformal quantile, so enabling weighting costs nothing when nothing has
#' moved.
#'
#' Four limits are worth stating plainly.
#'
#' It addresses **covariate shift only**. The guarantee assumes the conditional
#' distribution of the outcome given the covariates is unchanged and only the
#' covariate distribution has moved. If the relationship itself has drifted --
#' label shift, concept drift, a changed measurement process -- reweighting
#' corrects nothing, and can be worse than useless by returning intervals that
#' look adjusted.
#'
#' The guarantee assumes the density ratio is **known exactly**. In practice it
#' is estimated from a finite batch by [attest_density_ratio()], so coverage is
#' approximate rather than guaranteed, and the error grows as the estimate gets
#' harder.
#'
#' Under strong shift the weighted calibration set has a small **effective
#' sample size**: a few heavily weighted scores carry the quantile, which makes
#' it noisy and generally conservative. Expect over-coverage and wide intervals
#' well before the method fails outright.
#'
#' The quantile becomes **infinite** when a point's own weight is large relative
#' to the calibration set. That is the honest answer -- no finite interval is
#' justified -- and [predict.attested_model()] refuses such rows rather than
#' reporting an unbounded one.
#' @references
#' Tibshirani, R. J., Barber, R. F., Candes, E. J. and Ramdas, A. (2019)
#' Conformal Prediction Under Covariate Shift. \emph{Advances in Neural
#' Information Processing Systems}.
#' @examples
#' s <- c(0.1, 0.2, 0.3, 0.4, 0.9)
#' attest_weighted_quantile(s, rep(1, 5), c(1, 5), alpha = 0.2)
#' @export
attest_weighted_quantile <- function(scores, w_calib, w_new, alpha = 0.1) {
  stopifnot(length(scores) == length(w_calib))
  ok <- is.finite(scores) & is.finite(w_calib) & w_calib > 0
  scores <- scores[ok]
  w_calib <- w_calib[ok]
  if (!length(scores)) {
    return(rep(Inf, length(w_new)))
  }

  ord <- order(scores)
  s <- scores[ord]
  cw <- cumsum(w_calib[ord])
  total <- cw[length(cw)]

  # For each new point the target mass is (1 - alpha) * (sum(w_calib) + w_new).
  # Only the denominator changes per point, so the cumulative sums are built
  # once and searched, rather than re-sorting for every row.
  need <- (1 - alpha) * (total + w_new)
  idx <- findInterval(need, cw, left.open = TRUE) + 1L
  out <- rep(Inf, length(w_new))
  hit <- idx <= length(s)
  out[hit] <- s[idx[hit]]
  out
}
