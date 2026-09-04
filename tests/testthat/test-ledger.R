mk_model <- function(seed = 1, n = 1000) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
  d$y <- factor(rbinom(n, 1, plogis(d$x1 - d$x2)))
  attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
}

new_ledger <- function(key = NULL) {
  p <- tempfile(fileext = ".ndjson")
  attest_ledger(p, key = key)
}

# Stand-in for a determined tamperer: edit a record, then reseal every entry
# so the chain is internally consistent again.
rechain <- function(path, key) {
  es <- lapply(readLines(path), jsonlite::fromJSON, simplifyVector = TRUE)
  es[[1]]$note <- "forged"
  prev <- "genesis"
  out <- character(0)
  for (i in seq_along(es)) {
    e <- es[[i]]
    e$digest <- NULL
    e$prev <- prev
    e$seq <- i
    e <- e[order(names(e))]
    e$digest <- attest:::seal_entry(e, key)
    prev <- e$digest
    out <- c(out, attest:::canonical_json(e))
  }
  writeLines(out, path)
}

test_that("a manifest carries the identifying facts of a certificate", {
  m <- mk_model()
  mf <- attest_manifest(m)
  expect_equal(mf$certificate_id, certificate(m)$id)
  expect_equal(mf$hash_model, certificate(m)$hashes$model)
  expect_equal(mf$hash_spec, certificate(m)$hashes$spec)
  expect_equal(mf$hash_data, certificate(m)$hashes$data)
  expect_equal(mf$engine, "glm")
  expect_equal(mf$task, "classification")
  expect_true(nzchar(mf$r_version))
  expect_true(nzchar(mf$platform))
  # plain data, so it survives a round trip through JSON
  expect_type(unlist(mf), "character")
})

test_that("entries append in order and the chain verifies", {
  led <- new_ledger()
  expect_length(ledger_entries(led), 0)

  ledger_append(led, mk_model(1), note = "run A")
  ledger_append(led, mk_model(2), note = "run B")
  ledger_append(led, mk_model(3))

  es <- ledger_entries(led)
  expect_length(es, 3)
  expect_equal(vapply(es, function(e) as.integer(e$seq), integer(1)), 1:3)
  expect_equal(as.character(es[[1]]$prev), "genesis")
  expect_equal(as.character(es[[2]]$prev), as.character(es[[1]]$digest))
  expect_equal(as.character(es[[3]]$prev), as.character(es[[2]]$digest))
  expect_equal(as.character(es[[1]]$note), "run A")

  v <- ledger_verify(led)
  expect_true(v)
  expect_length(attr(v, "problems"), 0)
  expect_equal(attr(v, "n"), 3)
})

test_that("editing an entry breaks its digest", {
  led <- new_ledger()
  ledger_append(led, mk_model(1), note = "run A")
  ledger_append(led, mk_model(2), note = "run B")

  ln <- readLines(led$path)
  ln[1] <- sub('"run A"', '"tampered"', ln[1], fixed = TRUE)
  writeLines(ln, led$path)

  v <- ledger_verify(led)
  expect_false(v)
  expect_match(attr(v, "problems")[1], "entry 1: digest")
})

test_that("deleting an entry breaks the chain that followed it", {
  led <- new_ledger()
  for (s in 1:3) ledger_append(led, mk_model(s))
  writeLines(readLines(led$path)[-2], led$path)

  v <- ledger_verify(led)
  expect_false(v)
  expect_true(any(grepl("does not follow", attr(v, "problems"))))
})

test_that("a plain digest does not survive a rewritten chain, and says so", {
  # Documents the boundary the help text states: without a key the log is
  # tamper-evident against accident and single edits, not against someone
  # who rebuilds it.
  led <- new_ledger()
  for (s in 1:3) ledger_append(led, mk_model(s))
  rechain(led$path, NULL)
  expect_true(ledger_verify(led))
})

test_that("an HMAC ledger cannot be rewritten without the key", {
  led <- new_ledger(key = "s3cret")
  for (s in 1:3) ledger_append(led, mk_model(s))
  expect_true(ledger_verify(led))

  rechain(led$path, NULL) # attacker seals with a plain digest
  expect_false(ledger_verify(led))

  led2 <- new_ledger(key = "s3cret")
  for (s in 1:3) ledger_append(led2, mk_model(s))
  rechain(led2$path, "guess") # attacker guesses
  expect_false(ledger_verify(led2))
})

test_that("an HMAC ledger needs the right key to verify at all", {
  p <- tempfile(fileext = ".ndjson")
  ledger_append(attest_ledger(p, key = "s3cret"), mk_model(1))
  expect_true(ledger_verify(attest_ledger(p, key = "s3cret")))
  expect_false(ledger_verify(attest_ledger(p, key = "wrong")))
  expect_false(ledger_verify(attest_ledger(p)))
})

test_that("ledger_find locates a certificate by model or id", {
  led <- new_ledger()
  m1 <- mk_model(1)
  m2 <- mk_model(2)
  ledger_append(led, m1)
  ledger_append(led, m2)

  expect_equal(ledger_find(led, m2)$certificate_id, certificate(m2)$id)
  expect_equal(
    ledger_find(led, certificate(m1)$id)$certificate_id,
    certificate(m1)$id
  )
  expect_null(ledger_find(led, "no-such-id"))
})

test_that("verify() checks a model against the ledger", {
  led <- new_ledger()
  m <- mk_model(1)
  other <- mk_model(7)
  ledger_append(led, m)

  expect_true(verify(m, ledger = led))

  r <- verify(other, ledger = led)
  expect_false(r)
  expect_true("not in ledger" %in% attr(r, "diff"))

  # a model altered after recording fails on its own hash too
  m2 <- m
  m2$model$coefficients[1] <- 99
  r2 <- verify(m2, ledger = led)
  expect_false(r2)
  expect_true("model" %in% attr(r2, "diff"))
})

test_that("verify() reports a broken chain even when the entry is present", {
  led <- new_ledger()
  m <- mk_model(1)
  ledger_append(led, m)
  ledger_append(led, mk_model(2))

  ln <- readLines(led$path)
  ln[2] <- sub('"note":""', '"note":"x"', ln[2], fixed = TRUE)
  writeLines(ln, led$path)

  r <- verify(m, ledger = led)
  expect_false(r)
  expect_true("ledger chain broken" %in% attr(r, "diff"))
})

test_that("verify() still works without a ledger", {
  m <- mk_model(1)
  expect_true(verify(m))
  expect_true(verify(m, data = data.frame(x1 = 1, x2 = 2)))
})

test_that("a ledger survives being reopened from its path", {
  p <- tempfile(fileext = ".ndjson")
  m <- mk_model(1)
  ledger_append(attest_ledger(p), m)
  reopened <- attest_ledger(p)
  expect_length(ledger_entries(reopened), 1)
  expect_true(ledger_verify(reopened))
  expect_true(verify(m, ledger = reopened))
})
