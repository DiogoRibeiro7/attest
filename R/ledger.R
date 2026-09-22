#' Build a portable manifest for an attested model
#'
#' A manifest is the certificate reduced to the facts that identify it: the
#' three hashes, what was fitted, and the environment it was fitted in. It is
#' plain data, so it can be written to a file, sent to someone who does not
#' have the model, and compared later.
#'
#' @param x An `attested_model`.
#' @return A named list.
#' @family certificates
#' @family ledgers
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' str(attest_manifest(m))
#' @export
attest_manifest <- function(x) {
  stopifnot(inherits(x, "attested_model"))
  ce <- x$certificate
  list(
    certificate_id = ce$id,
    issued = ce$issued,
    status = ce$status,
    hash_data = ce$hashes$data,
    hash_spec = ce$hashes$spec,
    hash_model = ce$hashes$model,
    engine = ce$engine,
    split = ce$split,
    task = ce$task,
    outcome = ce$outcome,
    features = paste(ce$features, collapse = ","),
    n_train = unname(ce$n[["train"]]),
    n_calib = unname(ce$n[["calib"]]),
    n_test = unname(ce$n[["test"]]),
    waived = if (is.null(ce$waivers)) "" else paste(ce$waivers$ids, collapse = ","),
    attest_version = ce$attest_version,
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform
  )
}

# Deterministic JSON, so that the same manifest always digests to the same
# value: names sorted at every level, no pretty printing, scalars unboxed.
canonical_json <- function(x) {
  sortr <- function(v) {
    if (is.list(v) && !is.null(names(v))) {
      v <- v[order(names(v))]
      v <- lapply(v, sortr)
    }
    v
  }
  as.character(jsonlite::toJSON(sortr(x), auto_unbox = TRUE, digits = NA, null = "null"))
}

seal_entry <- function(entry, key) {
  payload <- canonical_json(entry)
  if (is.null(key)) {
    digest::digest(payload, algo = "sha256", serialize = FALSE)
  } else {
    digest::hmac(key, payload, algo = "sha256")
  }
}

#' An append-only ledger of issued certificates
#'
#' Records every certificate a project issues in a newline-delimited JSON file.
#' Each entry carries the digest of the entry before it, so the file is a chain:
#' altering or removing any earlier record breaks every digest after it, and
#' [ledger_verify()] reports where.
#'
#' @details
#' Be precise about what the seal proves, because the two modes differ in kind
#' rather than in degree.
#'
#' Without `key`, entries are sealed with a plain SHA-256 digest. Because each
#' entry also carries the previous entry's digest, editing or deleting a single
#' record is caught: every later entry still points at the digest the record
#' used to have. What a plain digest does **not** withstand is someone
#' rewriting the whole chain, which anyone with the package can do. Treat it as
#' a tamper-evident log against accident, corruption and casual editing -- not
#' as a signature.
#'
#' With a secret `key`, entries are sealed with an HMAC, and a rewritten chain
#' cannot be resealed without the key. That is a real integrity guarantee, and
#' it rests entirely on the key: anyone holding it can rewrite the ledger
#' undetectably. Keep it out of the ledger, out of the repository and out of
#' the script that writes it.
#'
#' The ledger records that a certificate was issued and what it covered. It is
#' not a guarantee that the model behind it still exists or is unchanged --
#' [verify()] compares a model in hand against the record.
#'
#' Appending reads the file and rewrites one line, which is not safe against two
#' processes writing at once.
#'
#' @param path Path to the ledger file. Created on first append.
#' @param key Optional secret key. When given, entries are sealed with an HMAC
#'   and the same key is needed to verify them.
#' @return An object of class `attest_ledger`.
#' @family ledgers
#' @examples
#' led <- attest_ledger(tempfile(fileext = ".ndjson"))
#' led
#' @export
attest_ledger <- function(path, key = NULL) {
  stopifnot(is.character(path), length(path) == 1)
  if (!is.null(key) && !is.character(key)) {
    rlang::abort("`key` must be a character string")
  }
  structure(list(path = path, key = key), class = "attest_ledger")
}

#' @export
print.attest_ledger <- function(x, ...) {
  n <- if (file.exists(x$path)) length(ledger_entries(x)) else 0L
  cli::cli_text(
    "<attest_ledger> {.file {x$path}} -- {n} entr{?y/ies}",
    "{if (is.null(x$key)) '' else ', HMAC sealed'}"
  )
  invisible(x)
}

#' Append a certificate to a ledger
#'
#' @param ledger An [attest_ledger()].
#' @param x An `attested_model`.
#' @param note Optional free text stored with the entry, such as the run or
#'   pipeline that produced the model.
#' @return The ledger, invisibly.
#' @family ledgers
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' led <- attest_ledger(tempfile(fileext = ".ndjson"))
#' ledger_append(led, m, note = "nightly run")
#' nrow(ledger_entries(led))
#' @export
ledger_append <- function(ledger, x, note = NULL) {
  stopifnot(inherits(ledger, "attest_ledger"), inherits(x, "attested_model"))
  prior <- if (file.exists(ledger$path)) ledger_entries(ledger) else list()
  prev <- if (length(prior)) prior[[length(prior)]]$digest else "genesis"

  entry <- c(
    list(seq = length(prior) + 1L, prev = prev),
    attest_manifest(x),
    list(
      recorded = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
      note = if (is.null(note)) "" else as.character(note)
    )
  )
  entry$digest <- seal_entry(entry, ledger$key)

  dir <- dirname(ledger$path)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  cat(canonical_json(entry), "\n", sep = "", file = ledger$path, append = TRUE)
  invisible(ledger)
}

#' Read the entries of a ledger
#'
#' @param ledger An [attest_ledger()].
#' @return A list of entries, oldest first. Empty if the file does not exist.
#' @family ledgers
#' @examples
#' led <- attest_ledger(tempfile(fileext = ".ndjson"))
#' length(ledger_entries(led))
#' @export
ledger_entries <- function(ledger) {
  stopifnot(inherits(ledger, "attest_ledger"))
  if (!file.exists(ledger$path)) {
    return(list())
  }
  lines <- readLines(ledger$path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  lapply(lines, function(l) {
    jsonlite::fromJSON(l, simplifyVector = TRUE)
  })
}

#' Verify the integrity of a ledger chain
#'
#' Recomputes each entry's digest and checks that it carries the digest of the
#' entry before it. An entry that has been altered fails on its own digest;
#' an entry that has been removed or reordered breaks the link in the entry
#' that followed it.
#'
#' @param ledger An [attest_ledger()].
#' @return A logical, `TRUE` when the chain is intact, with attribute
#'   `"problems"` describing any breaks.
#' @family ledgers
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' led <- attest_ledger(tempfile(fileext = ".ndjson"))
#' ledger_append(led, m)
#' ledger_verify(led)
#' @export
ledger_verify <- function(ledger) {
  stopifnot(inherits(ledger, "attest_ledger"))
  entries <- ledger_entries(ledger)
  problems <- character(0)
  prev <- "genesis"
  for (i in seq_along(entries)) {
    e <- entries[[i]]
    recorded <- e$digest
    e$digest <- NULL
    if (!identical(seal_entry(e, ledger$key), recorded)) {
      problems <- c(problems, sprintf("entry %d: digest does not match its contents", i))
    }
    if (!identical(as.character(e$prev), prev)) {
      problems <- c(problems, sprintf("entry %d: does not follow entry %d", i, i - 1L))
    }
    if (!identical(as.integer(e$seq), i)) {
      problems <- c(problems, sprintf("entry %d: sequence number is %s", i, e$seq))
    }
    prev <- recorded
  }
  structure(length(problems) == 0, problems = problems, n = length(entries))
}

#' Find the ledger entry for a model
#'
#' @param ledger An [attest_ledger()].
#' @param x An `attested_model`, or a certificate id.
#' @return The matching entry, or `NULL`.
#' @family ledgers
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' led <- attest_ledger(tempfile(fileext = ".ndjson"))
#' ledger_append(led, m)
#' ledger_find(led, m)$certificate_id
#' @export
ledger_find <- function(ledger, x) {
  id <- if (inherits(x, "attested_model")) x$certificate$id else as.character(x)
  entries <- ledger_entries(ledger)
  hit <- Filter(function(e) identical(as.character(e$certificate_id), id), entries)
  if (!length(hit)) {
    return(NULL)
  }
  hit[[length(hit)]]
}
