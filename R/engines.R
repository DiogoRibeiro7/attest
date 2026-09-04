#' Engine adapters
#'
#' An engine is a thin adapter around a modelling function. Three generics
#' define the interface: [engine_fit()] and [engine_predict()].
#'
#' @param ... Arguments passed to the underlying fitting function.
#' @return An object of class `attest_engine`.
#' @name engines
NULL

new_engine <- function(id, ..., class) {
  structure(list(id = id, args = list(...)), class = c(class, "attest_engine"))
}

#' @rdname engines
#' @export
engine_glm <- function(...) new_engine("glm", ..., class = "engine_glm")

#' @rdname engines
#' @export
engine_ranger <- function(...) {
  rlang::check_installed("ranger")
  new_engine("ranger", ..., class = "engine_ranger")
}

#' @export
print.attest_engine <- function(x, ...) {
  cat("<attest_engine> ", x$id, "\n", sep = "")
  invisible(x)
}

#' Fit a model with an engine
#'
#' @param engine An `attest_engine`.
#' @param formula Model formula.
#' @param data Training data.
#' @param task `"classification"` or `"regression"`.
#' @return A fitted object.
#' @export
engine_fit <- function(engine, formula, data, task) UseMethod("engine_fit")

#' Predict from an engine-fitted object
#'
#' @inheritParams engine_fit
#' @param object The fitted object.
#' @param newdata Data to predict on.
#' @param type `"prob"` (probability of the second factor level) or `"numeric"`.
#' @return A numeric vector.
#' @export
engine_predict <- function(engine, object, newdata, type = c("prob", "numeric")) {
  UseMethod("engine_predict")
}

#' @export
engine_fit.engine_glm <- function(engine, formula, data, task) {
  fam <- if (task == "classification") stats::binomial() else stats::gaussian()
  fit <- do.call(stats::glm, c(list(formula = formula, data = data, family = fam), engine$args))
  fit$call <- quote(attest::engine_fit())
  fit
}

#' @export
engine_predict.engine_glm <- function(engine, object, newdata, type = c("prob", "numeric")) {
  as.numeric(stats::predict(object, newdata = newdata, type = "response"))
}

#' @export
engine_fit.engine_ranger <- function(engine, formula, data, task) {
  args <- c(list(formula = formula, data = data), engine$args)
  if (task == "classification") args$probability <- TRUE
  fit <- do.call(ranger::ranger, args)
  fit$call <- quote(attest::engine_fit())
  fit
}

#' @export
engine_predict.engine_ranger <- function(engine, object, newdata, type = c("prob", "numeric")) {
  p <- stats::predict(object, data = newdata)$predictions
  if (is.matrix(p)) as.numeric(p[, 2]) else as.numeric(p)
}

# ---- Splits ----------------------------------------------------------------

#' Split strategies
#'
#' A split returns integer row indices for `train`, `calib` and `test`.
#'
#' @param prop Proportion of rows held out for testing.
#' @param calib Proportion of the remaining rows held out for conformal
#'   calibration.
#' @param group Name of a grouping column; whole groups are assigned to one
#'   partition.
#' @param time Name of a time column; the latest rows become the test set.
#' @return An object of class `attest_split`.
#' @name splits
NULL

new_split <- function(id, ..., class) {
  structure(list(id = id, ...), class = c(class, "attest_split"))
}

#' @rdname splits
#' @export
split_random <- function(prop = 0.2, calib = 0.2) {
  new_split("split_random", prop = prop, calib = calib, class = "split_random")
}

#' @rdname splits
#' @export
split_grouped <- function(group, prop = 0.2, calib = 0.2) {
  new_split("split_grouped", group = group, prop = prop, calib = calib, class = "split_grouped")
}

#' @rdname splits
#' @export
split_temporal <- function(time, prop = 0.2, calib = 0.2) {
  new_split("split_temporal", time = time, prop = prop, calib = calib, class = "split_temporal")
}

#' @export
print.attest_split <- function(x, ...) {
  cat("<attest_split> ", x$id, "\n", sep = "")
  invisible(x)
}

do_split <- function(split, data) UseMethod("do_split")

carve_calib <- function(train_idx, calib) {
  n_cal <- floor(calib * length(train_idx))
  cal <- if (n_cal > 0) sample(train_idx, n_cal) else integer(0)
  list(train = setdiff(train_idx, cal), calib = cal)
}

#' @export
do_split.split_random <- function(split, data) {
  n <- nrow(data)
  test <- sample(seq_len(n), floor(split$prop * n))
  rest <- carve_calib(setdiff(seq_len(n), test), split$calib)
  c(rest, list(test = test))
}

#' @export
do_split.split_grouped <- function(split, data) {
  g <- data[[split$group]]
  if (is.null(g)) rlang::abort(sprintf("group column `%s` not found", split$group))
  ug <- unique(g)
  test_g <- sample(ug, floor(split$prop * length(ug)))
  test <- which(g %in% test_g)
  rest_idx <- setdiff(seq_len(nrow(data)), test)
  rest_g <- unique(g[rest_idx])
  cal_g <- sample(rest_g, floor(split$calib * length(rest_g)))
  calib <- rest_idx[g[rest_idx] %in% cal_g]
  list(train = setdiff(rest_idx, calib), calib = calib, test = test)
}

#' @export
do_split.split_temporal <- function(split, data) {
  t <- data[[split$time]]
  if (is.null(t)) rlang::abort(sprintf("time column `%s` not found", split$time))
  ord <- order(t)
  n <- length(ord)
  n_test <- floor(split$prop * n)
  test <- ord[(n - n_test + 1):n]
  rest <- ord[seq_len(n - n_test)]
  n_cal <- floor(split$calib * length(rest))
  calib <- if (n_cal > 0) rest[(length(rest) - n_cal + 1):length(rest)] else integer(0)
  list(train = setdiff(rest, calib), calib = calib, test = test)
}
