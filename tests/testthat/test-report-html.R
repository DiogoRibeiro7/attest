card_model <- function(n = 3000, seed = 7) {
  set.seed(seed)
  d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), x3 = runif(n, 0, 10))
  d$y <- factor(rbinom(n, 1, plogis(0.9 * d$x1 - 0.5 * d$x2)))
  list(
    model = attest_fit(attest_spec(), y ~ x1 + x2 + x3, d, engine_glm(), quiet = TRUE),
    data = d
  )
}

svg_blocks <- function(lines) {
  txt <- paste(lines, collapse = "\n")
  regmatches(txt, gregexpr("<svg .*?</svg>", txt))[[1]]
}

test_that("the certificate carries what the charts need", {
  fx <- card_model()
  res <- certificate(fx$model)$results
  b <- res$calib_ece$evidence$bins
  expect_false(is.null(b))
  expect_equal(length(b$confidence), length(b$observed))
  expect_equal(length(b$confidence), length(b$n))
  expect_true(all(b$confidence >= 0 & b$confidence <= 1))
  expect_true(all(b$observed >= 0 & b$observed <= 1))

  cv <- res$conformal_split$evidence$curve
  expect_false(is.null(cv))
  expect_equal(length(cv$alpha), length(cv$coverage))
  expect_true(all(cv$coverage >= 0 & cv$coverage <= 1))
})

test_that("chart data reproduces the statistics the certificate reports", {
  # The card must not be able to disagree with the model it describes, so the
  # stored bins and curve have to be the same numbers the checks used.
  fx <- card_model()
  res <- certificate(fx$model)$results

  b <- res$calib_ece$evidence$bins
  ece <- sum((b$n / sum(b$n)) * abs(b$observed - b$confidence))
  expect_equal(ece, res$calib_ece$statistic)

  cv <- res$conformal_split$evidence$curve
  a <- res$conformal_split$evidence$alpha
  expect_equal(
    cv$coverage[which.min(abs(cv$alpha - a))],
    res$conformal_split$statistic
  )
})

test_that("the coverage curve falls as alpha rises", {
  fx <- card_model()
  cv <- certificate(fx$model)$results$conformal_split$evidence$curve
  expect_true(all(diff(cv$coverage) <= 1e-12))
})

test_that("report() still defaults to Markdown", {
  fx <- card_model(1500)
  md <- report(fx$model)
  expect_true(any(grepl("^# Model card", md)))
  expect_false(any(grepl("<svg", md)))
})

test_that("the HTML card is self-contained", {
  fx <- card_model(1500)
  h <- report(fx$model, format = "html")
  txt <- paste(h, collapse = "\n")
  expect_true(grepl("<!DOCTYPE html>", txt, fixed = TRUE))
  expect_true(grepl("</html>", txt, fixed = TRUE))
  # nothing is fetched from anywhere
  expect_false(grepl("src=", txt, fixed = TRUE))
  expect_false(grepl("href=", txt, fixed = TRUE))
  expect_false(grepl("@import", txt, fixed = TRUE))
  # The one URL in the file is the SVG namespace, which is an identifier rather
  # than an address: nothing is loaded from it, and standalone SVG needs it.
  urls <- regmatches(txt, gregexpr("https?://[^\" ]+", txt))[[1]]
  expect_true(all(urls == "http://www.w3.org/2000/svg"))
})

test_that("the card carries the certificate facts", {
  fx <- card_model(1500)
  ce <- certificate(fx$model)
  txt <- paste(report(fx$model, format = "html"), collapse = "\n")
  expect_true(grepl(ce$id, txt, fixed = TRUE))
  expect_true(grepl(ce$engine, txt, fixed = TRUE))
  expect_true(grepl(substr(ce$hashes$model, 1, 12), txt, fixed = TRUE))
  for (id in names(ce$results)) expect_true(grepl(id, txt, fixed = TRUE))
})

test_that("the charts are well-formed SVG inside the viewBox", {
  fx <- card_model(1500)
  blocks <- svg_blocks(report(fx$model, format = "html"))
  expect_gte(length(blocks), 2)
  nums <- function(s) {
    v <- as.numeric(unlist(strsplit(gsub("[^-0-9. ]", " ", gsub(",", " ", s)), " +")))
    v[!is.na(v)]
  }
  for (s in blocks) {
    # parses on its own, not only as part of the page
    expect_silent(xml2::read_xml(s))
    vb <- nums(regmatches(s, regexpr('(?<=viewBox=")[^"]+', s, perl = TRUE)))
    expect_length(vb, 4)
    for (p in regmatches(s, gregexpr('(?<=points=")[^"]+', s, perl = TRUE))[[1]]) {
      co <- nums(p)
      xs <- co[c(TRUE, FALSE)]
      ys <- co[c(FALSE, TRUE)]
      expect_true(all(xs >= 0 & xs <= vb[3]))
      expect_true(all(ys >= 0 & ys <= vb[4]))
    }
  }
})

test_that("a batch adds a shift section and is otherwise absent", {
  fx <- card_model(3000)
  plain <- paste(report(fx$model, format = "html"), collapse = "\n")
  expect_false(grepl("Shift on the supplied batch", plain, fixed = TRUE))

  batch <- fx$data[1:400, ]
  batch$x1 <- batch$x1 + 1.5
  withbatch <- paste(
    report(fx$model, format = "html", newdata = batch),
    collapse = "\n"
  )
  expect_true(grepl("Shift on the supplied batch", withbatch, fixed = TRUE))
  expect_true(grepl("stability index", withbatch, fixed = TRUE))
})

test_that("a waiver is reproduced in the card", {
  set.seed(3)
  d <- data.frame(x1 = rnorm(2000))
  d$y <- factor(rbinom(2000, 1, plogis(d$x1)))
  d$leak <- as.integer(d$y)
  m <- suppressWarnings(attest_fit(attest_spec(), y ~ x1 + leak, d, engine_glm(),
    waive = "leak_target_proxy", reason = "validated rating factor",
    quiet = TRUE
  ))
  txt <- paste(report(m, format = "html"), collapse = "\n")
  expect_true(grepl("Waivers", txt, fixed = TRUE))
  expect_true(grepl("validated rating factor", txt, fixed = TRUE))
})

test_that("text from the data cannot inject markup", {
  set.seed(4)
  d <- data.frame(x1 = rnorm(1500))
  d$y <- factor(rbinom(1500, 1, plogis(d$x1)))
  d$leak <- as.integer(d$y)
  m <- suppressWarnings(attest_fit(attest_spec(), y ~ x1 + leak, d, engine_glm(),
    waive = "leak_target_proxy",
    reason = "<script>alert(1)</script> & \"quoted\"",
    quiet = TRUE
  ))
  txt <- paste(report(m, format = "html"), collapse = "\n")
  expect_false(grepl("<script>", txt, fixed = TRUE))
  expect_true(grepl("&lt;script&gt;", txt, fixed = TRUE))
  expect_true(grepl("&amp;", txt, fixed = TRUE))
})

test_that("the card writes to a file when asked", {
  fx <- card_model(1500)
  f <- tempfile(fileext = ".html")
  on.exit(unlink(f), add = TRUE)
  invisible(report(fx$model, f, format = "html"))
  expect_true(file.exists(f))
  expect_gt(file.size(f), 2000)
  expect_true(any(grepl("</html>", readLines(f, warn = FALSE), fixed = TRUE)))
})

test_that("a regression model produces a card without a reliability diagram", {
  set.seed(6)
  d <- data.frame(x = rnorm(1500))
  d$y <- 2 * d$x + rnorm(1500)
  m <- attest_fit(attest_spec(), y ~ x, d, engine_glm(), quiet = TRUE)
  h <- report(m, format = "html")
  txt <- paste(h, collapse = "\n")
  expect_true(grepl("</html>", txt, fixed = TRUE))
  # ECE is untestable for regression, so that chart is simply absent
  expect_false(grepl("Reliability diagram", txt, fixed = TRUE))
  expect_true(grepl("Empirical coverage", txt, fixed = TRUE))
})
