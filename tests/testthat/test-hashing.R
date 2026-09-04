test_that("the spec hash is reproducible across identical specifications", {
  h <- function(s) attest:::hash_obj(attest:::spec_fingerprint(s))
  same <- replicate(20, identical(h(attest_spec()), h(attest_spec())))
  expect_true(all(same))
})

test_that("the spec hash survives just-in-time compilation", {
  # Serialising a closure is not stable: R attaches bytecode to a function once
  # it has run a few times, so the same check hashes differently before and
  # after use. The fingerprint is structural and must not move.
  h <- function(s) attest:::hash_obj(attest:::spec_fingerprint(s))
  s <- attest_spec()
  before <- h(s)
  for (i in 1:100) invisible(attest_spec())
  expect_equal(h(s), before)
})

test_that("hashing a closure directly is not stable, which is why we do not", {
  mk <- function() function(x) x + 1
  f <- mk()
  before <- attest:::hash_obj(f)
  for (i in 1:100) f(1)
  # documents the behaviour the fingerprint exists to avoid
  expect_false(identical(attest:::hash_obj(f), before))
})

test_that("the spec hash responds to configuration", {
  h <- function(s) attest:::hash_obj(attest:::spec_fingerprint(s))
  base <- h(attest_spec())
  expect_false(h(attest_spec(on_fail = "flag")) == base)
  expect_false(h(attest_spec(strict = TRUE)) == base)
  expect_false(h(attest_spec(split = split_random(prop = 0.3))) == base)

  # thresholds live in the check's enclosing environment and must count
  a <- h(attest_spec(checks = list(calib_ece(max = 0.05))))
  b <- h(attest_spec(checks = list(calib_ece(max = 0.10))))
  expect_false(a == b)

  # and so does the set of checks
  expect_false(h(attest_spec(checks = list(calib_ece()))) == base)
})

test_that("spec_fingerprint copes with a check that takes no arguments", {
  # imbalance_report() closes over nothing, so its environment is empty
  s <- attest_spec(checks = list(imbalance_report(), conformal_split()))
  expect_silent(attest:::spec_fingerprint(s))
  expect_type(attest:::hash_obj(attest:::spec_fingerprint(s)), "character")
})

test_that("identical fits produce identical certificate ids", {
  mk <- function() {
    set.seed(99)
    d <- data.frame(x1 = rnorm(1200), x2 = rnorm(1200))
    d$y <- factor(rbinom(1200, 1, plogis(d$x1)))
    set.seed(5)
    attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  }
  a <- mk()
  b <- mk()
  expect_equal(certificate(a)$id, certificate(b)$id)
  expect_equal(certificate(a)$hashes, certificate(b)$hashes)
})

test_that("a different specification produces a different certificate", {
  d <- local({
    set.seed(2)
    d <- data.frame(x1 = rnorm(1200), x2 = rnorm(1200))
    d$y <- factor(rbinom(1200, 1, plogis(d$x1)))
    d
  })
  fit_with <- function(spec) {
    set.seed(5)
    attest_fit(spec, y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  }
  a <- fit_with(attest_spec())
  b <- fit_with(attest_spec(checks = c(default_checks(), list(shift_c2st()))))
  expect_false(certificate(a)$hashes$spec == certificate(b)$hashes$spec)
  expect_false(certificate(a)$id == certificate(b)$id)
})

test_that("the seal survives a save and reload for the base engines", {
  set.seed(3)
  d <- data.frame(x1 = rnorm(1200), x2 = rnorm(1200))
  d$y <- factor(rbinom(1200, 1, plogis(d$x1)))
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  saveRDS(m, f)
  back <- readRDS(f)
  expect_true(is_sealed(back))
  expect_true(verify(back))
  expect_equal(certificate(back)$id, certificate(m)$id)
})

test_that("repeated prediction does not spontaneously break the seal", {
  set.seed(3)
  d <- data.frame(x1 = rnorm(1200), x2 = rnorm(1200))
  d$y <- factor(rbinom(1200, 1, plogis(d$x1)))
  m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
  for (i in 1:50) invisible(predict(m, d[1:2, ]))
  expect_true(is_sealed(m))
})
