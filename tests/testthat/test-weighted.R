test_that("the weighted quantile reduces to split conformal under equal weights", {
  set.seed(1)
  for (n in c(5, 20, 79, 200)) {
    for (alpha in c(0.05, 0.1, 0.2, 0.33)) {
      s <- sort(runif(n))
      k <- ceiling((n + 1) * (1 - alpha))
      std <- if (k > n) Inf else s[k]
      expect_equal(
        attest_weighted_quantile(s, rep(1, n), 1, alpha), std,
        info = sprintf("n=%d alpha=%.2f", n, alpha)
      )
    }
  }
})

test_that("a test point far heavier than the calibration set gets an infinite quantile", {
  set.seed(2)
  s <- sort(runif(50))
  q <- attest_weighted_quantile(s, rep(1, 50), c(1, 1e4), alpha = 0.1)
  expect_true(is.finite(q[1]))
  expect_true(is.infinite(q[2]))
})

test_that("weighting the tail moves the quantile in the expected direction", {
  set.seed(3)
  s <- sort(runif(300))
  discounted <- attest_weighted_quantile(s, ifelse(s > 0.8, 0.1, 1), 1, 0.1)
  uniform <- attest_weighted_quantile(s, rep(1, 300), 1, 0.1)
  emphasised <- attest_weighted_quantile(s, ifelse(s > 0.8, 10, 1), 1, 0.1)
  expect_lt(discounted, uniform)
  expect_gt(emphasised, uniform)
})

test_that("the weighted quantile is vectorised over the points being predicted", {
  set.seed(4)
  s <- sort(runif(100))
  q <- attest_weighted_quantile(s, rep(1, 100), c(1, 2, 3, 4), alpha = 0.1)
  expect_length(q, 4)
  expect_true(all(diff(q) >= 0)) # heavier points get wider quantiles
})

test_that("the density ratio separates shifted samples and not unshifted ones", {
  set.seed(5)
  a <- data.frame(x = rnorm(400), z = rnorm(400))
  same <- data.frame(x = rnorm(400), z = rnorm(400))
  shifted <- data.frame(x = rnorm(400, 1.5), z = rnorm(400))

  r_same <- attest_density_ratio(a, same, c("x", "z"))
  r_shift <- attest_density_ratio(a, shifted, c("x", "z"))

  expect_lt(abs(r_same$auc - 0.5), 0.1)
  expect_gt(r_shift$auc, 0.7)
  expect_length(r_same$calib, 400)
  expect_length(r_same$new, 400)
  expect_true(all(r_shift$new > 0))
})

test_that("the density ratio falls back to flat weights when it cannot fit", {
  a <- data.frame(x = rnorm(5))
  b <- data.frame(x = rnorm(5))
  r <- attest_density_ratio(a, b, "x")
  expect_equal(r$auc, 0.5)
  expect_true(all(r$calib == 1))
})

test_that("weighted = TRUE stores the calibration material and adds .weight", {
  set.seed(6)
  d <- data.frame(x1 = rnorm(1500), x2 = rnorm(1500))
  d$y <- 2 * d$x1 - d$x2 + rnorm(1500)
  spec <- attest_spec(checks = list(
    conformal_split(weighted = TRUE),
    shift_monitor()
  ))
  m <- attest_fit(spec, y ~ x1 + x2, d, engine_glm(), quiet = TRUE)

  ev <- certificate(m)$results$conformal_split$evidence
  expect_true(isTRUE(ev$weighted))
  expect_equal(length(ev$calib_scores), ev$n_calib)
  expect_equal(nrow(ev$calib_x), ev$n_calib)

  p <- predict(m, d[1:50, ])
  expect_true(".weight" %in% names(p))
  expect_true(all(p$.weight > 0))
})

test_that("without weighted = TRUE there is no .weight column and q is fixed", {
  set.seed(7)
  d <- data.frame(x1 = rnorm(1500), x2 = rnorm(1500))
  d$y <- 2 * d$x1 - d$x2 + rnorm(1500)
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  p <- predict(m, d[1:50, ])
  expect_false(".weight" %in% names(p))
  # every row shares the one certificate quantile
  expect_equal(length(unique(round(p$.upper - p$.lower, 9))), 1L)
})

test_that("reweighting recovers coverage that a fixed quantile loses under shift", {
  set.seed(8)
  gen <- function(n, mu = 0) {
    x1 <- rnorm(n, mu)
    x2 <- rnorm(n)
    data.frame(x1 = x1, x2 = x2, y = 2 * x1 - x2 + rnorm(n, sd = 0.4 + abs(x1)))
  }
  train <- gen(4000)
  mw <- attest_fit(
    attest_spec(checks = list(conformal_split(weighted = TRUE), shift_monitor())),
    y ~ x1 + x2, train, engine_glm(),
    quiet = TRUE
  )
  mp <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x1 + x2, train, engine_glm(),
    quiet = TRUE
  )
  cover <- function(m, nd) {
    p <- suppressWarnings(predict(m, nd, enforce = FALSE))
    ok <- is.finite(p$.lower) & is.finite(p$.upper)
    mean(nd$y[ok] >= p$.lower[ok] & nd$y[ok] <= p$.upper[ok])
  }
  shifted <- gen(600, mu = 1.5)
  cp <- cover(mp, shifted)
  cw <- cover(mw, shifted)
  # the fixed quantile falls well short of 0.9; reweighting closes most of it
  expect_lt(cp, 0.85)
  expect_gt(cw, cp + 0.05)
})

test_that("reweighting leaves unshifted batches essentially unchanged", {
  set.seed(9)
  d <- data.frame(x1 = rnorm(3000), x2 = rnorm(3000))
  d$y <- 2 * d$x1 - d$x2 + rnorm(3000)
  mw <- attest_fit(
    attest_spec(checks = list(conformal_split(weighted = TRUE), shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  mp <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  nd <- d[1:400, ]
  wp <- predict(mp, nd)
  ww <- predict(mw, nd)
  plain_width <- mean(wp$.upper - wp$.lower, na.rm = TRUE)
  weighted_width <- mean(ww$.upper - ww$.lower, na.rm = TRUE)
  expect_lt(abs(weighted_width - plain_width) / plain_width, 0.25)
})

test_that("weighted conformal works for classification and yields label sets", {
  set.seed(10)
  d <- data.frame(x1 = rnorm(2000), x2 = rnorm(2000))
  d$y <- factor(rbinom(2000, 1, plogis(d$x1 - d$x2)))
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(weighted = TRUE), shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  p <- predict(m, d[1:40, ])
  expect_true(".set" %in% names(p))
  expect_true(all(grepl("^\\{", stats::na.omit(p$.set))))
  expect_true(".weight" %in% names(p))
})

test_that("printing a subset of a prediction does not warn about dropped columns", {
  set.seed(11)
  d <- data.frame(x1 = rnorm(1200), x2 = rnorm(1200))
  d$y <- 2 * d$x1 - d$x2 + rnorm(1200)
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  p <- predict(m, d[1:20, ])
  expect_no_warning(print(p[, c(".pred", ".lower")]))
  expect_no_warning(print(p))
})
