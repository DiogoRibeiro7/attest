#' Engine adapters
#'
#' An engine is a thin adapter around a modelling function. Three generics
#' define the interface: [engine_fit()] and [engine_predict()].
#'
#' @param ... Arguments passed to the underlying fitting function.
#' @return An object of class `attest_engine`.
#' @family engines
#' @examples
#' engine_glm()
#' engine_glm(weights = NULL)
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

#' Fit any parsnip model under a certificate
#'
#' Wraps a parsnip model specification, so anything parsnip can fit --
#' `boost_tree()` on xgboost, `linear_reg()` on glmnet, `rand_forest()` on
#' ranger, and the rest -- can be certified without writing an adapter for each.
#'
#' @details
#' The specification's mode is set from the task inferred by [attest_fit()], so
#' the usual `set_mode()` call is unnecessary. A mode that contradicts the
#' outcome is an error rather than a silent correction.
#'
#' The certificate records the specification rather than the bare word
#' `"parsnip"`, as `parsnip:<model>/<engine>` -- for example
#' `parsnip:boost_tree/xgboost` -- so a model card says what was actually
#' fitted.
#'
#' attest needs a probability for the second outcome level, which parsnip
#' supplies through `type = "prob"`. An engine offering no probabilities cannot
#' be calibrated or given conformal label sets, and is rejected at fit time
#' rather than issuing a certificate whose checks mean nothing.
#'
#' @param spec A parsnip `model_spec`, such as `parsnip::logistic_reg()`.
#' @return An object of class `attest_engine`.
#' @family engines
#' @examples
#' if (requireNamespace("parsnip", quietly = TRUE)) {
#'   engine_parsnip(parsnip::logistic_reg())
#' }
#' @export
engine_parsnip <- function(spec) {
  rlang::check_installed("parsnip")
  if (!inherits(spec, "model_spec")) {
    rlang::abort("`spec` must be a parsnip model specification")
  }
  eng <- spec$engine %||% "default"
  id <- sprintf("parsnip:%s/%s", class(spec)[1], eng)
  structure(
    list(id = id, args = list(), spec = spec),
    class = c("engine_parsnip", "attest_engine")
  )
}

#' @export
engine_fit.engine_parsnip <- function(engine, formula, data, task) {
  spec <- engine$spec
  want <- if (is_classification(task)) "classification" else "regression"
  have <- spec$mode %||% "unknown"
  if (have %in% c("unknown", "")) {
    spec <- parsnip::set_mode(spec, want)
  } else if (!identical(have, want)) {
    rlang::abort(sprintf(
      "engine mode is %s but the outcome implies %s", have, want
    ))
  }
  fit <- parsnip::fit(spec, formula, data = data)
  if (task == "classification" && length(fit$lvl) != 2) {
    rlang::abort("a two-level outcome was expected but the fit has more")
  }
  # Timing varies between otherwise identical fits and would make the model
  # hash depend on how fast the machine was.
  fit$elapsed <- NULL
  fit
}

#' @export
engine_predict.engine_parsnip <- function(engine, object, newdata,
                                          type = c("prob", "numeric", "prob_matrix")) {
  type <- match.arg(type)
  if (identical(object$spec$mode, "classification")) {
    p <- stats::predict(object, new_data = newdata, type = "prob")
    cols <- paste0(".pred_", object$lvl)
    missing <- setdiff(cols, names(p))
    if (length(missing)) {
      rlang::abort(sprintf(
        "parsnip returned no %s column",
        paste(missing, collapse = ", ")
      ))
    }
    if (type == "prob_matrix") {
      m <- as.matrix(p[, cols, drop = FALSE])
      colnames(m) <- object$lvl
      return(m)
    }
    return(as.numeric(p[[cols[2]]]))
  }
  as.numeric(stats::predict(object, new_data = newdata)$.pred)
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
#' @family engines
#' @examples
#' set.seed(1)
#' d <- data.frame(x = rnorm(400))
#' d$y <- factor(rbinom(400, 1, plogis(d$x)))
#' fit <- engine_fit(engine_glm(), y ~ x, d, "classification")
#' class(fit)
#' @export
engine_fit <- function(engine, formula, data, task) UseMethod("engine_fit")

#' Predict from an engine-fitted object
#'
#' @inheritParams engine_fit
#' @param object The fitted object.
#' @param newdata Data to predict on.
#' @param type `"prob"` (probability of the second factor level), `"numeric"`,
#'   or `"prob_matrix"` (one column per class, in level order, for multiclass
#'   outcomes).
#' @return A numeric vector.
#' @family engines
#' @examples
#' set.seed(1)
#' d <- data.frame(x = rnorm(400))
#' d$y <- factor(rbinom(400, 1, plogis(d$x)))
#' fit <- engine_fit(engine_glm(), y ~ x, d, "classification")
#' head(engine_predict(engine_glm(), fit, d, type = "prob"))
#' @export
engine_predict <- function(engine, object, newdata,
                           type = c("prob", "numeric", "prob_matrix")) {
  UseMethod("engine_predict")
}

#' @export
engine_fit.engine_glm <- function(engine, formula, data, task) {
  if (identical(task, "multiclass")) {
    rlang::abort(c(
      "engine_glm() fits binary outcomes only",
      "i" = "for a multiclass outcome use engine_ranger() or engine_parsnip()"
    ))
  }
  fam <- if (task == "classification") stats::binomial() else stats::gaussian()
  fit <- do.call(
    stats::glm,
    c(list(formula = formula, data = data, family = fam), engine$args)
  )
  fit$call <- quote(attest::engine_fit())
  fit
}

#' @export
engine_predict.engine_glm <- function(engine, object, newdata,
                                      type = c("prob", "numeric", "prob_matrix")) {
  type <- match.arg(type)
  if (type == "prob_matrix") {
    rlang::abort(c(
      "engine_glm() is binary only",
      "i" = "for a multiclass outcome use engine_ranger() or engine_parsnip()"
    ))
  }
  as.numeric(stats::predict(object, newdata = newdata, type = "response"))
}

#' @export
engine_fit.engine_ranger <- function(engine, formula, data, task) {
  args <- c(list(formula = formula, data = data), engine$args)
  if (is_classification(task)) args$probability <- TRUE
  fit <- do.call(ranger::ranger, args)
  fit$call <- quote(attest::engine_fit())
  fit
}

#' @export
engine_predict.engine_ranger <- function(engine, object, newdata,
                                         type = c("prob", "numeric", "prob_matrix")) {
  type <- match.arg(type)
  p <- stats::predict(object, data = newdata)$predictions
  if (type == "prob_matrix") {
    if (!is.matrix(p)) rlang::abort("engine did not return class probabilities")
    return(p)
  }
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
#' @family splitting
#' @examples
#' split_random(prop = 0.25, calib = 0.2)
#' split_grouped("customer_id")
#' split_temporal("order_date", prop = 0.3)
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
  new_split(
    "split_grouped",
    group = group, prop = prop, calib = calib, class = "split_grouped"
  )
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
