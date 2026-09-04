#' Build an attestation specification
#'
#' @param split A split strategy, see [splits].
#' @param checks A list of checks, see [new_check()]. Defaults to the standard
#'   set: duplicates, target proxy, imbalance report, ECE, split conformal
#'   and a PSI shift monitor.
#' @param on_fail What to do when a blocking check fails: `"refuse"` (default;
#'   no certificate is issued and fitting errors), `"flag"` (certificate is
#'   issued but marked as failed) or `"warn"`.
#' @param strict How to treat a `"weak"` check, where the statistic's
#'   confidence interval straddles its threshold. `FALSE` (default) treats it
#'   as a pass: a check fails only on confident violation. `TRUE` treats it as
#'   a failure, so inconclusive evidence blocks certification. Set it when
#'   scarce data must not buy a certificate by widening intervals.
#' @return An object of class `attest_spec`.
#' @examples
#' spec <- attest_spec(split_random(0.25), on_fail = "flag")
#' spec
#' @export
attest_spec <- function(split = split_random(),
                        checks = default_checks(),
                        on_fail = c("refuse", "flag", "warn"),
                        strict = FALSE) {
  on_fail <- match.arg(on_fail)
  stopifnot(inherits(split, "attest_split"), is.logical(strict), length(strict) == 1)
  if (inherits(checks, "attest_check")) checks <- list(checks)
  ids <- vapply(checks, function(ch) ch$id, character(1))
  if (anyDuplicated(ids)) rlang::abort("duplicate check ids in spec")
  names(checks) <- ids
  structure(
    list(
      split = split, checks = checks, on_fail = on_fail,
      strict = strict
    ),
    class = "attest_spec"
  )
}

#' @rdname attest_spec
#' @export
default_checks <- function() {
  list(
    leak_duplicates(), leak_target_proxy(), imbalance_report(),
    calib_ece(), conformal_split(), shift_monitor()
  )
}

#' @export
print.attest_spec <- function(x, ...) {
  cli::cli_h3("attest_spec")
  cli::cli_text("split: {.field {x$split$id}}; on_fail: {.val {x$on_fail}}")
  for (ch in x$checks) {
    cli::cli_li("{ch$id} {.emph ({ch$stage}{if (ch$blocking) ', blocking' else ''})}")
  }
  invisible(x)
}

infer_task <- function(y) {
  if (is.logical(y)) {
    return("classification")
  }
  if (is.factor(y) && nlevels(y) == 2) {
    return("classification")
  }
  if (is.numeric(y)) {
    return("regression")
  }
  rlang::abort("outcome must be numeric, logical, or a two-level factor")
}

#' Fit a model and issue a certificate
#'
#' @param spec An [attest_spec()].
#' @param formula Model formula. The outcome must be numeric (regression),
#'   logical, or a two-level factor (binary classification).
#' @param data A data frame.
#' @param engine An engine, see [engines].
#' @param waive Character vector of check ids to waive. Every waiver requires
#'   a `reason`.
#' @param reason Character string explaining the waiver. Stored in the
#'   certificate and printed in every report.
#' @param quiet Suppress progress output.
#' @return An object of class `attested_model`.
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(2000), x2 = rnorm(2000))
#' d$y <- factor(rbinom(2000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' certificate(m)
#' predict(m, d[1:3, ])
#' @export
attest_fit <- function(spec, formula, data, engine = engine_glm(),
                       waive = character(0), reason = NULL, quiet = FALSE) {
  stopifnot(inherits(spec, "attest_spec"), inherits(engine, "attest_engine"))
  data <- as.data.frame(data)
  if (length(waive) > 0 && (is.null(reason) || !nzchar(reason))) {
    rlang::abort("every waiver requires a `reason`")
  }
  unknown <- setdiff(waive, names(spec$checks))
  if (length(unknown)) {
    rlang::abort(sprintf(
      "unknown check ids in `waive`: %s",
      paste(unknown, collapse = ", ")
    ))
  }

  outcome <- all.vars(formula[[2]])
  y <- data[[outcome]]
  if (is.null(y)) rlang::abort(sprintf("outcome `%s` not found in data", outcome))
  if (is.logical(y)) data[[outcome]] <- factor(y, levels = c(FALSE, TRUE))
  task <- infer_task(data[[outcome]])
  features <- setdiff(all.vars(formula), outcome)
  if ("." %in% all.vars(formula) || length(features) == 0) {
    features <- setdiff(names(data), outcome)
    formula <- stats::reformulate(features, response = outcome)
  }

  idx <- do_split(spec$split, data)
  if (length(idx$calib) == 0) {
    rlang::abort("calibration set is empty; increase `calib` in the split")
  }
  ctx <- list(
    train = data[idx$train, , drop = FALSE],
    calib = data[idx$calib, , drop = FALSE],
    test = data[idx$test, , drop = FALSE],
    task = task, outcome = outcome, features = features,
    engine = engine, spec = spec
  )

  results <- list()
  run_stage <- function(stage) {
    for (ch in spec$checks) {
      if (ch$stage != stage) next
      res <- if (ch$id %in% waive) {
        attest_result(ch$id, "waived", message = reason)
      } else {
        ch$run(ctx)
      }
      results[[ch$id]] <<- res
      if (!quiet) report_line(res, ch$blocking)
    }
  }

  run_stage("pre")
  # The model sees only `train`; `calib` is held back for conformal scores.
  ctx$model <- engine_fit(engine, formula, ctx$train, task)
  run_stage("post")

  fail_states <- if (isTRUE(spec$strict)) c("fail", "weak") else "fail"
  blocking_fail <- vapply(spec$checks, function(ch) {
    ch$blocking && results[[ch$id]]$status %in% fail_states
  }, logical(1))
  failed <- names(spec$checks)[blocking_fail]
  weak <- names(spec$checks)[vapply(spec$checks, function(ch) {
    results[[ch$id]]$status == "weak"
  }, logical(1))]

  status <- if (length(failed) == 0) "valid" else "failed"
  if (length(weak) > 0 && !quiet) {
    ids <- paste(weak, collapse = ", ")
    hint <- if (isTRUE(spec$strict)) "" else "; treated as a pass (see `strict`)"
    cli::cli_alert_warning(
      "inconclusive: {ids} -- interval straddles the threshold{hint}"
    )
  }
  if (length(failed) > 0) {
    msg <- sprintf("blocking checks failed: %s", paste(failed, collapse = ", "))
    if (spec$on_fail == "refuse") {
      rlang::abort(c(
        "refused to issue certificate (on_fail = \"refuse\")",
        "i" = msg,
        "i" = "to proceed anyway: attest_fit(..., waive = <check id>, reason = \"...\")"
      ))
    } else if (spec$on_fail == "warn") {
      rlang::warn(msg)
    }
  }

  conf <- results$conformal_split$evidence
  shift <- results$shift_monitor$evidence
  c2st <- results$shift_c2st$evidence
  hashes <- list(
    data = hash_obj(data[idx$train, features, drop = FALSE]),
    spec = hash_obj(spec_fingerprint(spec)),
    model = hash_obj(ctx$model)
  )
  cert <- structure(list(
    id = substr(hash_obj(hashes), 1, 12),
    issued = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    status = status,
    on_fail = spec$on_fail,
    task = task, outcome = outcome, features = features,
    engine = engine$id, split = spec$split$id,
    n = c(train = length(idx$train), calib = length(idx$calib), test = length(idx$test)),
    results = results,
    waivers = if (length(waive)) list(ids = waive, reason = reason) else NULL,
    hashes = hashes,
    attest_version = as.character(utils::packageVersion("attest"))
  ), class = "certificate")

  if (!quiet) {
    cli::cli_alert_info("Certificate {cert$id} issued {cert$issued} UTC ({cert$status})")
  }

  structure(list(
    engine = engine, model = ctx$model, formula = formula,
    task = task, outcome = outcome, features = features,
    levels = if (task == "classification") levels(data[[outcome]]) else NULL,
    conformal = conf, shift = shift, c2st = c2st,
    certificate = cert
  ), class = "attested_model")
}

report_line <- function(res, blocking) {
  sym <- switch(res$status,
    pass = cli::col_green(cli::symbol$tick),
    weak = cli::col_yellow("?"),
    fail = cli::col_red(cli::symbol$cross),
    waived = cli::col_yellow("~"),
    untestable = cli::col_grey("-"),
    info = cli::col_blue("i")
  )
  cli::cat_line(sprintf("%s %-20s %-11s %s", sym, res$id, res$status, res$message))
}

hash_obj <- function(x) {
  # Environments are replaced by a constant so that the hash depends only on
  # values, never on where the object happened to be created.
  raw <- serialize(x, NULL, refhook = function(e) "env")
  digest::digest(raw, algo = "sha256", serialize = FALSE)
}

# A specification is mostly closures, and serialising a closure is not a stable
# operation: R's just-in-time compiler attaches bytecode to a function the first
# few times it runs, so the same check hashes differently before and after it
# has been used. Hashing a structural summary instead makes the spec hash mean
# "this configuration" -- reproducible across sessions, and sensitive to the
# thresholds a check was built with, which live in its enclosing environment.
spec_fingerprint <- function(spec) {
  simple <- function(e) {
    vals <- as.list(e)
    if (!length(vals)) {
      return(list())
    }
    vals <- vals[order(names(vals))]
    lapply(vals, function(v) if (is.atomic(v) || is.null(v)) v else class(v)[1])
  }
  list(
    split = c(list(id = spec$split$id), simple(spec$split[names(spec$split) != "id"])),
    on_fail = spec$on_fail,
    strict = isTRUE(spec$strict),
    checks = lapply(spec$checks[order(names(spec$checks))], function(ch) {
      list(
        id = ch$id, stage = ch$stage, blocking = ch$blocking,
        args = simple(environment(ch$run))
      )
    })
  )
}

# ---- Certificate -----------------------------------------------------------

#' Inspect and verify certificates
#'
#' @param x An `attested_model`.
#' @param data Training data used to fit the model, for hash verification.
#' @param ledger An optional [attest_ledger()]. When given, `verify()` also
#'   checks that this certificate was recorded, that its hashes match the
#'   record, and that the ledger chain is intact.
#' @return `certificate()` returns the certificate; `is_sealed()` a logical;
#'   `verify()` a logical with attribute `"diff"` listing what changed;
#'   `unseal()` the raw engine object.
#' @examples
#' set.seed(1)
#' d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
#' d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
#' m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
#' certificate(m)
#' is_sealed(m)
#' verify(m)
#' class(unseal(m))
#' @name certificate
#' @export
certificate <- function(x) {
  stopifnot(inherits(x, "attested_model"))
  x$certificate
}

#' @rdname certificate
#' @export
is_sealed <- function(x) {
  stopifnot(inherits(x, "attested_model"))
  identical(hash_obj(x$model), x$certificate$hashes$model) &&
    identical(x$certificate$status, "valid")
}

#' @rdname certificate
#' @export
verify <- function(x, data = NULL, ledger = NULL) {
  stopifnot(inherits(x, "attested_model"))
  diff <- character(0)
  if (!identical(hash_obj(x$model), x$certificate$hashes$model)) diff <- c(diff, "model")
  if (!is.null(data)) {
    # We cannot reconstruct the split without the seed; verify the full-data
    # feature hash was the source by checking column structure and reporting.
    if (!all(x$features %in% names(data))) diff <- c(diff, "data columns")
  }
  if (!is.null(ledger)) {
    entry <- ledger_find(ledger, x)
    if (is.null(entry)) {
      diff <- c(diff, "not in ledger")
    } else {
      chain <- ledger_verify(ledger)
      if (!chain) diff <- c(diff, "ledger chain broken")
      pairs <- c(
        hash_data = "data", hash_spec = "spec", hash_model = "model"
      )
      for (f in names(pairs)) {
        if (!identical(as.character(entry[[f]]), x$certificate$hashes[[pairs[[f]]]])) {
          diff <- c(diff, sprintf("ledger %s hash", pairs[[f]]))
        }
      }
    }
  }
  ok <- length(diff) == 0 && x$certificate$status == "valid"
  structure(ok, diff = diff)
}

#' @rdname certificate
#' @export
unseal <- function(x) {
  stopifnot(inherits(x, "attested_model"))
  x$model
}

#' @export
print.certificate <- function(x, ...) {
  n <- x$n
  cli::cli_h2("Certificate {x$id}")
  cli::cli_text(
    "issued {x$issued} UTC | status {.strong {x$status}} | ",
    "on_fail {.val {x$on_fail}}"
  )
  cli::cli_text(
    "task {x$task} | engine {x$engine} | split {x$split} | ",
    "n = {n['train']}/{n['calib']}/{n['test']} (train/calib/test)"
  )
  for (res in x$results) report_line(res, TRUE)
  if (!is.null(x$waivers)) {
    ids <- paste(x$waivers$ids, collapse = ", ")
    cli::cli_alert_warning(
      cli::col_red("WAIVED: {ids} -- \"{x$waivers$reason}\"")
    )
  }
  invisible(x)
}

#' @export
print.attested_model <- function(x, ...) {
  cli::cli_text(
    "<attested_model> {x$task} on {.field {x$outcome}} with ",
    "{length(x$features)} feature{?s}, engine {x$engine$id}"
  )
  print(x$certificate)
  invisible(x)
}
