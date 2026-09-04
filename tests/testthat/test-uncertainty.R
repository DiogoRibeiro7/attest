make_data <- function(n = 2000, seed = 1) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), g = factor(sample(c("a", "b", "c"), n, TRUE)))
  d$y <- factor(rbinom(n, 1, plogis(0.8 * d$x1 - 0.5 * d$x2)))
  d
}

test_that("attest_verdict fails only when the interval clears the threshold", {
  # at_most: statistic should not exceed the threshold
  expect_equal(attest_verdict(0.20, c(0.15, 0.25), 0.10, "at_most"), "fail")
  expect_equal(attest_verdict(0.04, c(0.02, 0.06), 0.10, "at_most"), "pass")
  expect_equal(attest_verdict(0.09, c(0.04, 0.15), 0.10, "at_most"), "weak")
  # a statistic above the threshold is still only weak if the interval covers it
  expect_equal(attest_verdict(0.12, c(0.04, 0.15), 0.10, "at_most"), "weak")

  # at_least: statistic should not fall below the threshold
  expect_equal(attest_verdict(0.70, c(0.65, 0.75), 0.87, "at_least"), "fail")
  expect_equal(attest_verdict(0.95, c(0.92, 0.97), 0.87, "at_least"), "pass")
  expect_equal(attest_verdict(0.88, c(0.85, 0.91), 0.87, "at_least"), "weak")

  # boundary: an interval touching the threshold passes, it has not cleared it
  expect_equal(attest_verdict(0.05, c(0.01, 0.10), 0.10, "at_most"), "pass")
})

test_that("attest_verdict falls back to the point estimate without an interval", {
  expect_equal(attest_verdict(0.20, c(NA, NA), 0.10, "at_most"), "fail")
  expect_equal(attest_verdict(0.05, c(NA, NA), 0.10, "at_most"), "pass")
  expect_equal(attest_verdict(0.70, c(NA, NA), 0.87, "at_least"), "fail")
  # "weak" is never reached without an interval
  expect_false(attest_verdict(0.20, c(NA, NA), 0.10, "at_most") == "weak")
})

test_that("attest_boot brackets a known quantity and honours n_boot = 0", {
  set.seed(3)
  y <- rbinom(4000, 1, 0.3)
  ci <- attest_boot(function(i) mean(y[i]), length(y), n_boot = 400)
  expect_length(ci, 2)
  expect_lt(ci[1], 0.3)
  expect_gt(ci[2], 0.3)
  expect_true(all(is.na(attest_boot(function(i) mean(y[i]), length(y), n_boot = 0))))
})

test_that("checks carry a confidence interval into the certificate", {
  d <- make_data()
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + g, d, engine_glm(), quiet = TRUE)
  res <- certificate(m)$results
  for (id in c("calib_ece", "conformal_split", "leak_target_proxy")) {
    ci <- res[[id]]$ci
    expect_length(ci, 2)
    expect_false(anyNA(ci), info = id)
    expect_lte(ci[1], res[[id]]$statistic)
    expect_gte(ci[2], res[[id]]$statistic)
  }
  # duplicates is a census, not an estimate, so it carries no interval
  expect_true(all(is.na(res$leak_duplicates$ci)))
  # and the interval reaches the model card
  expect_true(any(grepl("95% CI", report(m), fixed = TRUE)))
})

test_that("n_boot = 0 disables intervals and restores point-estimate verdicts", {
  d <- make_data()
  spec <- attest_spec(checks = list(
    calib_ece(n_boot = 0), conformal_split(n_boot = 0),
    shift_monitor()
  ))
  m <- attest_fit(spec, y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  res <- certificate(m)$results
  expect_true(all(is.na(res$calib_ece$ci)))
  expect_true(res$calib_ece$status %in% c("pass", "fail"))
})

test_that("a straddling interval yields weak, and strict promotes it to failure", {
  d <- make_data()
  # with a threshold far below the interval, the whole interval clears it:
  # a confident failure, which the default on_fail = "refuse" turns into an error
  tight <- attest_spec(checks = list(calib_ece(max = 1e-4), shift_monitor()))
  expect_error(
    attest_fit(tight, y ~ x1 + x2, d, engine_glm(), quiet = TRUE),
    "refused to issue certificate"
  )
  m <- attest_fit(
    attest_spec(
      checks = list(calib_ece(max = 1e-4), shift_monitor()),
      on_fail = "flag"
    ),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  expect_equal(certificate(m)$results$calib_ece$status, "fail")

  # find a threshold that genuinely straddles
  ci <- certificate(
    attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  )$results$calib_ece$ci
  mid <- mean(ci)
  spec <- attest_spec(checks = list(calib_ece(max = mid), shift_monitor()))
  mw <- attest_fit(spec, y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  expect_equal(certificate(mw)$results$calib_ece$status, "weak")
  # weak is not a failure by default
  expect_equal(certificate(mw)$status, "valid")
  expect_true(is_sealed(mw))

  strict <- attest_spec(checks = list(calib_ece(max = mid), shift_monitor()), strict = TRUE)
  expect_error(
    attest_fit(strict, y ~ x1 + x2, d, engine_glm(), quiet = TRUE),
    "refused to issue certificate"
  )
})

test_that("attest_result rejects a malformed interval and accepts weak", {
  expect_error(attest_result("x", "pass", ci = 0.5), "length 2")
  r <- attest_result("x", "weak", statistic = 0.04, threshold = 0.05, ci = c(0.02, 0.09))
  expect_equal(r$status, "weak")
  expect_equal(r$ci, c(0.02, 0.09))
})

test_that("PSI null calibration suppresses false flags on small unshifted batches", {
  d <- make_data(n = 3000)
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  set.seed(9)
  flagged <- replicate(25, {
    s <- d[sample(nrow(d), 60, replace = TRUE), ]
    any(predict(m, s)$.status == "flagged")
  })
  # with a fixed 0.2 threshold this fires most of the time; calibrated it is rare
  expect_lt(mean(flagged), 0.3)
})

test_that("a real shift is still flagged", {
  d <- make_data(n = 3000)
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  set.seed(9)
  s <- d[sample(nrow(d), 500, replace = TRUE), ]
  s$x1 <- s$x1 + 1
  p <- predict(m, s)
  expect_true(any(p$.status == "flagged"))
  expect_true(any(grepl("PSI", p$.reason[p$.status == "flagged"])))
})

test_that("shift_monitor n_boot = 0 keeps the fixed threshold", {
  d <- make_data(n = 3000)
  spec <- attest_spec(checks = c(default_checks()[1:5], list(shift_monitor(n_boot = 0))))
  m <- attest_fit(spec, y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  expect_equal(certificate(m)$results$shift_monitor$evidence$n_boot, 0)
  s <- d[sample(nrow(d), 500, replace = TRUE), ]
  s$x1 <- s$x1 + 1
  expect_true(any(predict(m, s)$.status == "flagged"))
})
