three_class <- function(n = 4000, seed = 21) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), x3 = rnorm(n))
  lp <- cbind(0, 1.2 * d$x1, 1.0 * d$x2 - 0.5 * d$x1)
  pr <- exp(lp) / rowSums(exp(lp))
  d$y <- factor(apply(pr, 1, function(p) sample(c("a", "b", "c"), 1, prob = p)))
  d
}

set_members <- function(s) strsplit(gsub("[{}]", "", s), ",")

test_that("the task is inferred from the number of outcome levels", {
  expect_equal(attest:::infer_task(rnorm(10)), "regression")
  expect_equal(attest:::infer_task(c(TRUE, FALSE, TRUE)), "classification")
  expect_equal(attest:::infer_task(factor(c("a", "b", "a"))), "classification")
  expect_equal(attest:::infer_task(factor(c("a", "b", "c"))), "multiclass")
  expect_equal(attest:::infer_task(factor(letters[1:8])), "multiclass")
  expect_error(attest:::infer_task(factor(rep("a", 5))), "fewer than two")
  expect_error(attest:::infer_task(as.Date("2020-01-01")), "must be numeric")
})

test_that("a multiclass outcome earns a certificate", {
  skip_if_not_installed("ranger")
  d <- three_class()
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + x3, d,
    engine_ranger(num.trees = 150),
    quiet = TRUE
  )
  expect_equal(certificate(m)$task, "multiclass")
  expect_equal(certificate(m)$status, "valid")
  expect_true(is_sealed(m))
  expect_equal(m$levels, c("a", "b", "c"))
})

test_that("multiclass predictions carry a class, a set and a confidence", {
  skip_if_not_installed("ranger")
  d <- three_class()
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + x3, d,
    engine_ranger(num.trees = 150),
    quiet = TRUE
  )
  p <- predict(m, d[1:50, ])
  expect_true(all(c(".pred", ".pred_class", ".set") %in% names(p)))
  expect_true(all(p$.pred_class %in% c("a", "b", "c")))
  # .pred stays numeric across tasks: the probability of the predicted class
  expect_true(all(p$.pred > 0 & p$.pred <= 1))
  members <- set_members(p$.set)
  expect_true(all(vapply(members, function(s) all(s %in% c("a", "b", "c")), logical(1))))
  expect_true(all(lengths(members) >= 1 & lengths(members) <= 3))
  # the predicted class is always inside its own set
  expect_true(all(mapply(function(s, cl) cl %in% s, members, p$.pred_class)))
})

test_that("conformal label sets cover the true class at the requested level", {
  skip_if_not_installed("ranger")
  train <- three_class(5000, seed = 21)
  fresh <- three_class(3000, seed = 99)
  for (a in c(0.1, 0.2)) {
    spec <- attest_spec(checks = list(conformal_split(alpha = a), shift_monitor()))
    m <- attest_fit(spec, y ~ x1 + x2 + x3, train,
      engine_ranger(num.trees = 150),
      quiet = TRUE
    )
    p <- predict(m, fresh)
    covered <- mapply(
      function(s, t) t %in% s,
      set_members(p$.set), as.character(fresh$y)
    )
    expect_gt(mean(covered), 1 - a - 0.05)
    expect_lt(mean(covered), 1 - a + 0.08)
  }
})

test_that("a looser alpha yields smaller sets", {
  skip_if_not_installed("ranger")
  train <- three_class(4000)
  sizes <- vapply(c(0.05, 0.2), function(a) {
    spec <- attest_spec(checks = list(conformal_split(alpha = a), shift_monitor()))
    m <- attest_fit(spec, y ~ x1 + x2 + x3, train,
      engine_ranger(num.trees = 150),
      quiet = TRUE
    )
    mean(lengths(set_members(predict(m, train[1:500, ])$.set)))
  }, numeric(1))
  expect_gt(sizes[1], sizes[2])
})

test_that("engine_glm refuses a multiclass outcome with a usable message", {
  d <- three_class(800)
  expect_error(
    attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE),
    "binary outcomes only"
  )
  expect_error(
    engine_predict(engine_glm(), NULL, d, type = "prob_matrix"),
    "binary only"
  )
})

test_that("parsnip handles a multiclass outcome", {
  skip_if_not_installed("parsnip")
  skip_if_not_installed("ranger")
  d <- three_class(3000)
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + x3, d,
    engine_parsnip(parsnip::rand_forest(trees = 100)),
    quiet = TRUE
  )
  expect_equal(certificate(m)$task, "multiclass")
  expect_true(is_sealed(m))
  p <- predict(m, d[1:20, ])
  expect_true(all(p$.pred_class %in% levels(d$y)))
})

test_that("the probability matrix has one column per level, in level order", {
  skip_if_not_installed("ranger")
  d <- three_class(2000)
  fit <- engine_fit(engine_ranger(num.trees = 50), y ~ x1 + x2, d, "multiclass")
  pm <- engine_predict(engine_ranger(), fit, d[1:10, ], type = "prob_matrix")
  expect_true(is.matrix(pm))
  expect_equal(ncol(pm), 3)
  expect_equal(colnames(pm), levels(d$y))
  expect_equal(unname(rowSums(pm)), rep(1, 10), tolerance = 1e-8)
})

test_that("checks that are binary-specific still run for multiclass", {
  skip_if_not_installed("ranger")
  d <- three_class(3000)
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + x3, d,
    engine_ranger(num.trees = 150),
    quiet = TRUE
  )
  res <- certificate(m)$results
  # imbalance now reports three classes rather than declining as untestable
  expect_equal(res$imbalance_report$status, "info")
  expect_equal(length(res$imbalance_report$evidence$table), 3L)
  # top-label ECE is computed, not skipped
  expect_false(res$calib_ece$status == "untestable")
  expect_true(is.finite(res$calib_ece$statistic))
  # single-feature strength is measured without a binary logistic fit
  expect_true(is.finite(res$leak_target_proxy$statistic))
})

test_that("a feature that determines a multiclass outcome is caught", {
  skip_if_not_installed("ranger")
  d <- three_class(2000)
  d$leak <- d$y # a perfect proxy
  expect_error(
    attest_fit(attest_spec(), y ~ x1 + leak, d,
      engine_ranger(num.trees = 50),
      quiet = TRUE
    ),
    "refused to issue certificate"
  )
})

test_that("weighted conformal works for multiclass", {
  skip_if_not_installed("ranger")
  d <- three_class(4000)
  spec <- attest_spec(checks = list(
    conformal_split(weighted = TRUE),
    shift_monitor()
  ))
  m <- attest_fit(spec, y ~ x1 + x2 + x3, d,
    engine_ranger(num.trees = 150),
    quiet = TRUE
  )
  nd <- three_class(500, seed = 55)
  nd$x1 <- nd$x1 + 1.5
  p <- predict(m, nd)
  expect_true(".weight" %in% names(p))
  expect_true(all(p$.weight > 0))
  expect_true(all(!is.na(p$.set[p$.status != "refused"])))
})

test_that("more than three classes work", {
  skip_if_not_installed("ranger")
  set.seed(9)
  n <- 4000
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  lp <- cbind(0, d$x1, 1.5 * d$x2, -d$x1 + d$x2, 0.8 * d$x1 - 0.8 * d$x2)
  pr <- exp(lp) / rowSums(exp(lp))
  d$y <- factor(letters[apply(pr, 1, function(p) sample(5, 1, prob = p))])
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d,
    engine_ranger(num.trees = 150),
    quiet = TRUE
  )
  expect_equal(length(m$levels), 5L)
  p <- predict(m, d[1:100, ])
  expect_true(all(lengths(set_members(p$.set)) <= 5))
})

test_that("the model card reports the multiclass task", {
  skip_if_not_installed("ranger")
  d <- three_class(2500)
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + x3, d,
    engine_ranger(num.trees = 100),
    quiet = TRUE
  )
  expect_true(any(grepl("multiclass", report(m))))
})

test_that("binary behaviour is unchanged", {
  set.seed(5)
  d <- data.frame(x1 = rnorm(2000), x2 = rnorm(2000))
  d$y <- factor(rbinom(2000, 1, plogis(d$x1 - d$x2)))
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  expect_equal(certificate(m)$task, "classification")
  p <- predict(m, d[1:10, ])
  expect_false(".pred_class" %in% names(p))
  expect_true(".set" %in% names(p))
})
