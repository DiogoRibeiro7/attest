gen_corr <- function(n, rho) {
  x <- rnorm(n)
  z <- rho * x + sqrt(1 - rho^2) * rnorm(n)
  data.frame(x = x, z = z, y = x + z + rnorm(n))
}

test_that("cross-fitted AUC is honest where an in-sample AUC is not", {
  set.seed(1)
  f <- c("x", "z")
  gen <- function(n) data.frame(x = rnorm(n), z = rnorm(n))
  reps <- replicate(20, {
    a <- gen(300)
    b <- gen(300)
    c(
      cross = attest_c2st(a, b, f)$auc,
      insample = attest_density_ratio(a, b, f)$auc
    )
  })
  # both samples come from the same distribution, so the truth is 0.5
  expect_lt(abs(mean(reps["cross", ]) - 0.5), 0.03)
  # the in-sample figure is optimistic: it exceeds the cross-fitted one
  expect_gt(mean(reps["insample", ]), mean(reps["cross", ]))
})

test_that("the two-sample test holds its size under no shift", {
  set.seed(2)
  f <- c("x", "z")
  gen <- function(n) data.frame(x = rnorm(n), z = rnorm(n))
  p <- replicate(40, attest_c2st(gen(400), gen(400), f)$p_value)
  expect_lt(mean(p < 0.05), 0.2)
  expect_gt(median(p), 0.2)
})

test_that("the two-sample test detects a mean shift", {
  set.seed(3)
  f <- c("x", "z")
  a <- data.frame(x = rnorm(500), z = rnorm(500))
  b <- data.frame(x = rnorm(500, 0.6), z = rnorm(500))
  r <- attest_c2st(a, b, f)
  expect_gt(r$auc, 0.6)
  expect_lt(r$p_value, 0.01)
})

test_that("the two-sample test detects a dependence change PSI cannot see", {
  set.seed(4)
  ref <- gen_corr(3000, 0.8)
  flipped <- gen_corr(800, -0.8)
  # identical marginals, opposite correlation
  expect_lt(abs(sd(ref$x) - sd(flipped$x)), 0.15)
  expect_lt(abs(sd(ref$z) - sd(flipped$z)), 0.15)

  r <- attest_c2st(ref, flipped, c("x", "z"))
  expect_gt(r$auc, 0.75)
  expect_lt(r$p_value, 1e-10)

  # the per-feature statistic sees nothing
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x + z, ref, engine_glm(),
    quiet = TRUE
  )
  expect_true(all(predict(m, flipped)$.status != "flagged"))
})

test_that("interactions are what make the dependence change visible", {
  set.seed(5)
  ref <- gen_corr(2000, 0.8)
  flipped <- gen_corr(800, -0.8)
  with_int <- attest_c2st(ref, flipped, c("x", "z"), interactions = TRUE)
  without <- attest_c2st(ref, flipped, c("x", "z"), interactions = FALSE)
  expect_gt(with_int$auc, without$auc + 0.15)
})

test_that("the test returns a null result on samples too small to judge", {
  set.seed(6)
  a <- data.frame(x = rnorm(10), z = rnorm(10))
  b <- data.frame(x = rnorm(10), z = rnorm(10))
  r <- attest_c2st(a, b, c("x", "z"))
  expect_equal(r$auc, 0.5)
  expect_equal(r$p_value, 1)
})

test_that("shift_c2st stores a bounded reference and flags a shifted batch", {
  set.seed(7)
  ref <- gen_corr(3000, 0.8)
  spec <- attest_spec(checks = c(default_checks(), list(shift_c2st(max_ref = 500))))
  m <- attest_fit(spec, y ~ x + z, ref, engine_glm(), quiet = TRUE)

  ev <- certificate(m)$results$shift_c2st$evidence
  expect_lte(nrow(ev$reference), 500)
  expect_true(all(c("x", "z") %in% names(ev$reference)))

  flipped <- gen_corr(600, -0.8)
  p <- predict(m, flipped)
  expect_true(all(p$.status == "flagged"))
  expect_true(any(grepl("C2ST", p$.reason)))
})

test_that("shift_c2st leaves an unshifted batch alone", {
  set.seed(8)
  ref <- gen_corr(3000, 0.8)
  spec <- attest_spec(checks = c(default_checks(), list(shift_c2st())))
  m <- attest_fit(spec, y ~ x + z, ref, engine_glm(), quiet = TRUE)
  flagged <- replicate(8, {
    any(predict(m, gen_corr(400, 0.8))$.status == "flagged")
  })
  expect_lt(mean(flagged), 0.4)
})

test_that("shift_c2st respects min_batch and the auc floor", {
  set.seed(9)
  ref <- gen_corr(2000, 0.8)
  m <- attest_fit(
    attest_spec(checks = c(default_checks(), list(shift_c2st(min_batch = 500)))),
    y ~ x + z, ref, engine_glm(),
    quiet = TRUE
  )
  # a batch below min_batch is never tested, however shifted
  small <- gen_corr(60, -0.8)
  expect_false(any(grepl("C2ST", stats::na.omit(predict(m, small)$.reason))))

  # an unreachable effect floor suppresses the flag
  m2 <- attest_fit(
    attest_spec(checks = c(default_checks(), list(shift_c2st(auc_min = 0.999)))),
    y ~ x + z, ref, engine_glm(),
    quiet = TRUE
  )
  expect_false(any(grepl("C2ST", stats::na.omit(predict(m2, gen_corr(600, -0.8))$.reason))))
})

test_that(".shift scores joint position, not per-feature tails", {
  set.seed(10)
  ref <- gen_corr(3000, 0.85)
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x + z, ref, engine_glm(),
    quiet = TRUE
  )
  nd <- gen_corr(200, 0.85)
  # unremarkable on each feature alone, implausible together given rho = 0.85
  nd[1, c("x", "z")] <- c(1.8, -1.8)
  p <- predict(m, nd)

  expect_true(abs(nd$x[1]) < max(abs(ref$x)))
  expect_true(abs(nd$z[1]) < max(abs(ref$z)))
  expect_gt(p$.shift[1], 0.99)
  expect_lt(stats::median(p$.shift[-1]), 0.9)
  expect_true(all(p$.shift >= 0 & p$.shift <= 1, na.rm = TRUE))
})

test_that(".shift falls back when there is nothing numeric to build on", {
  set.seed(11)
  d <- data.frame(
    g = factor(sample(c("a", "b", "c"), 800, TRUE)),
    h = factor(sample(c("p", "q"), 800, TRUE))
  )
  d$y <- factor(rbinom(800, 1, ifelse(d$g == "a", 0.7, 0.3)))
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ g + h, d, engine_glm(),
    quiet = TRUE
  )
  p <- predict(m, d[1:20, ])
  expect_true(all(is.finite(p$.shift)))
  expect_true(all(p$.shift >= 0 & p$.shift <= 1))
})
