binary_data <- function(n = 2000, seed = 12) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  d$y <- factor(rbinom(n, 1, plogis(1.2 * d$x1 - 0.6 * d$x2)))
  d
}

test_that("engine_parsnip rejects anything that is not a model spec", {
  skip_if_not_installed("parsnip")
  expect_error(engine_parsnip("logistic_reg"), "model specification")
  expect_error(engine_parsnip(list()), "model specification")
})

test_that("the engine id records the model and its engine", {
  skip_if_not_installed("parsnip")
  e <- engine_parsnip(parsnip::logistic_reg())
  expect_s3_class(e, "attest_engine")
  expect_equal(e$id, "parsnip:logistic_reg/glm")
  expect_match(
    engine_parsnip(parsnip::rand_forest(trees = 10))$id,
    "^parsnip:rand_forest/"
  )
})

test_that("a parsnip model earns a certificate and predicts", {
  skip_if_not_installed("parsnip")
  d <- binary_data()
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d,
    engine_parsnip(parsnip::logistic_reg()),
    quiet = TRUE
  )
  expect_s3_class(m, "attested_model")
  expect_equal(certificate(m)$status, "valid")
  expect_equal(certificate(m)$engine, "parsnip:logistic_reg/glm")
  expect_true(is_sealed(m))

  p <- predict(m, d[1:5, ])
  expect_s3_class(p, "attested_prediction")
  expect_true(all(p$.pred >= 0 & p$.pred <= 1))
  expect_true(all(p$.status == "valid"))
})

test_that("the mode follows the outcome, and a contradiction is an error", {
  skip_if_not_installed("parsnip")
  d <- binary_data(1200)
  # an unset mode is filled in from the task
  expect_equal(parsnip::rand_forest(trees = 10)$mode, "unknown")
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d,
    engine_parsnip(parsnip::rand_forest(trees = 30)),
    quiet = TRUE
  )
  expect_true(is_sealed(m))

  wrong <- parsnip::set_mode(parsnip::rand_forest(trees = 10), "regression")
  expect_error(
    attest_fit(attest_spec(), y ~ x1 + x2, d, engine_parsnip(wrong), quiet = TRUE),
    "outcome implies classification"
  )
})

test_that("regression through parsnip yields intervals", {
  skip_if_not_installed("parsnip")
  set.seed(4)
  d <- data.frame(x = rnorm(1200))
  d$y <- 2 * d$x + rnorm(1200)
  m <- attest_fit(attest_spec(), y ~ x, d,
    engine_parsnip(parsnip::linear_reg()),
    quiet = TRUE
  )
  p <- predict(m, d[1:5, ])
  expect_true(all(p$.lower < p$.pred & p$.pred < p$.upper))
})

test_that("parsnip reaches other back ends without a new adapter", {
  skip_if_not_installed("parsnip")
  # Enough rows that the model checks are stable. On a smaller sample the tree
  # back ends land near the coverage tolerance and the fit is refused, which is
  # the checks doing their job but not what this test is about.
  d <- binary_data(4000)
  for (pkg in c("ranger", "xgboost", "glmnet")) {
    skip_if_not_installed(pkg)
    spec <- switch(pkg,
      ranger = parsnip::rand_forest(trees = 40),
      xgboost = parsnip::set_engine(parsnip::boost_tree(trees = 25), "xgboost"),
      glmnet = parsnip::set_engine(parsnip::logistic_reg(penalty = 0.01), "glmnet")
    )
    m <- attest_fit(attest_spec(), y ~ x1 + x2, d,
      engine_parsnip(spec),
      quiet = TRUE
    )
    expect_true(is_sealed(m), info = pkg)
    expect_true(all(is.finite(predict(m, d[1:3, ])$.pred)), info = pkg)
  }
})

test_that("tampering with a parsnip fit breaks the seal", {
  skip_if_not_installed("parsnip")
  d <- binary_data(1200)
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d,
    engine_parsnip(parsnip::logistic_reg()),
    quiet = TRUE
  )
  expect_true(is_sealed(m))
  m$model$fit$coefficients[1] <- 99
  expect_false(is_sealed(m))
  expect_error(predict(m, d[1:2, ]), "not sealed")
})

test_that("a certificate survives a save and reload", {
  skip_if_not_installed("parsnip")
  d <- binary_data(1200)
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d,
    engine_parsnip(parsnip::logistic_reg()),
    quiet = TRUE
  )
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  saveRDS(m, f)
  back <- readRDS(f)
  expect_true(is_sealed(back))
  expect_equal(certificate(back)$id, certificate(m)$id)
  expect_equal(predict(back, d[1:3, ])$.pred, predict(m, d[1:3, ])$.pred)
})
