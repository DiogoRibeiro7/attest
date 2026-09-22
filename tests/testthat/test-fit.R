make_data <- function(n = 2000, seed = 1) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), g = factor(sample(c("a", "b", "c"), n, TRUE)))
  d$y <- factor(rbinom(n, 1, plogis(0.8 * d$x1 - 0.5 * d$x2)))
  d
}

test_that("fit issues a valid certificate and predictions carry status", {
  d <- make_data()
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + g, d, engine_glm(), quiet = TRUE)
  expect_s3_class(m, "attested_model")
  expect_true(is_sealed(m))
  expect_equal(certificate(m)$status, "valid")
  expect_equal(certificate(m)$results$leak_duplicates$label, "Duplicate row leakage")
  p <- predict(m, d[1:10, ])
  expect_s3_class(p, "attested_prediction")
  expect_true(all(p$.status == "valid"))
  expect_true(all(c(".pred", ".set", ".status", ".shift", ".reason") %in% names(p)))
})

test_that("checks and results carry human-readable labels", {
  d <- make_data()
  max_missing <- new_check(
    "max_missing",
    label = "Missingness guard", stage = "pre",
    run = function(ctx) {
      prop <- mean(is.na(ctx$train[ctx$features]))
      attest_result("max_missing", if (prop <= 0.05) "pass" else "fail",
        statistic = prop, threshold = 0.05
      )
    }
  )
  m <- attest_fit(
    attest_spec(checks = list(max_missing, conformal_split())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  expect_equal(certificate(m)$results$max_missing$label, "Missingness guard")
  expect_equal(attest_result("my_check", "info")$label, "My check")
})

test_that("out-of-support rows are refused unless enforce = FALSE", {
  d <- make_data()
  m <- attest_fit(attest_spec(), y ~ x1 + x2 + g, d, engine_glm(), quiet = TRUE)
  nd <- d[1:3, ]
  nd$x1[1] <- 50
  nd$x2[2] <- -60
  p <- predict(m, nd)
  expect_equal(p$.status, c("refused", "refused", "valid"))
  nd2 <- d[1:2, ]
  nd2$g <- factor(c("zzz", "a"))
  expect_equal(predict(m, nd2)$.status, c("refused", "valid"))
  expect_true(is.na(p$.pred[1]))
  p2 <- predict(m, nd, enforce = FALSE)
  expect_false(is.na(p2$.pred[1]))
  expect_false(attr(p2, "enforced"))
})

test_that("target proxy leakage refuses certification, waiver requires reason", {
  d <- make_data()
  d$leak <- as.integer(d$y) # perfect proxy
  expect_error(
    attest_fit(attest_spec(), y ~ x1 + leak, d, engine_glm(), quiet = TRUE),
    "refused to issue certificate"
  )
  expect_error(suppressWarnings(attest_fit(attest_spec(), y ~ x1 + leak, d, engine_glm(),
    quiet = TRUE,
    waive = "leak_target_proxy"
  )), "reason")
  m <- suppressWarnings(attest_fit(attest_spec(), y ~ x1 + leak, d, engine_glm(),
    quiet = TRUE,
    waive = "leak_target_proxy", reason = "test"
  ))
  expect_equal(certificate(m)$waivers$ids, "leak_target_proxy")
  expect_true(any(grepl("Waivers", report(m))))
})

test_that("on_fail = flag issues a failed certificate that cannot predict", {
  d <- make_data()
  d$leak <- as.integer(d$y)
  m <- suppressWarnings(attest_fit(
    attest_spec(on_fail = "flag"), y ~ x1 + leak, d, engine_glm(),
    quiet = TRUE
  ))
  expect_equal(certificate(m)$status, "failed")
  expect_false(is_sealed(m))
  expect_error(predict(m, d[1:2, ]), "not sealed")
})

test_that("regression works with intervals and temporal split", {
  set.seed(2)
  d <- data.frame(t = 1:500, x = rnorm(500))
  d$y <- 2 * d$x + rnorm(500)
  spec <- attest_spec(split_temporal("t"), checks = c(default_checks(), list(leak_temporal("t"))))
  m <- attest_fit(spec, y ~ x, d, engine_glm(), quiet = TRUE)
  p <- predict(m, d[1:5, ])
  expect_true(all(p$.lower < p$.pred & p$.pred < p$.upper))
  expect_equal(certificate(m)$results$leak_temporal$status, "pass")
})

test_that("tampering with the model breaks the seal", {
  d <- make_data()
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  m$model$coefficients[1] <- 99
  expect_false(is_sealed(m))
  expect_false(verify(m))
})

test_that("ranger engine works when available", {
  skip_if_not_installed("ranger")
  d <- make_data()
  m <- attest_fit(
    attest_spec(on_fail = "flag"), y ~ x1 + x2, d,
    engine_ranger(num.trees = 200),
    quiet = TRUE
  )
  expect_s3_class(m, "attested_model")
  expect_true(is.numeric(certificate(m)$results$calib_ece$statistic))
})

test_that("a specification without a conformal check says so", {
  # Without a calibrated quantile there is no interval, so every row is
  # refused. That is defensible, but it was reported as a reweighting
  # failure when no reweighting had taken place, and was silent at fit time.
  d <- make_data(1200)
  expect_warning(
    attest_fit(
      attest_spec(checks = list(shift_monitor())),
      y ~ x1 + x2, d, engine_glm()
    ),
    "no conformal check"
  )
  # the warning is the point of the test above; silence it here
  m <- suppressWarnings(attest_fit(
    attest_spec(checks = list(shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  ))
  p <- predict(m, d[1:10, ])
  expect_true(all(p$.status == "refused"))
  expect_match(unique(p$.reason), "no conformal check", all = TRUE)
  expect_false(any(grepl("reweighting", p$.reason)))
})

test_that("a specification with a conformal check predicts normally", {
  d <- make_data(1200)
  m <- attest_fit(
    attest_spec(checks = list(conformal_split(), shift_monitor())),
    y ~ x1 + x2, d, engine_glm(),
    quiet = TRUE
  )
  p <- predict(m, d[1:10, ])
  expect_true(all(p$.status == "valid"))
})
