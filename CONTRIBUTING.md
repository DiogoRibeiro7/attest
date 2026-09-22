# Contributing to attest

Thanks for considering a contribution.

## Reporting a problem

Open an issue with a [reprex](https://reprex.tidyverse.org) — a small, runnable
example that reproduces what you saw. For a check that fired when it should not
have, or failed to fire when it should have, please include the certificate:

```r
certificate(model)
```

That carries the statistic, the interval, the threshold and the verdict, which
is usually enough to tell a real defect from a threshold that needs setting for
your data.

## What kind of change fits

The package has a narrow contract, and changes are judged against it:

1. No certificate, no predictions.
2. A prediction is a value **and** a guarantee **and** a status.
3. Checks run at fit time, never on request.
4. Reports are rendered from the certificate, never recomputed.

A change that makes a check easier to skip, or that lets a report disagree with
the model it describes, will not be merged however convenient it is.

### Adding a check

Checks are the extension point and new ones are welcome. See `?new_check`. A
check should:

- return an `attest_result()` with a statistic, a threshold and a message;
- report a confidence interval where its statistic is estimated, and use
  `attest_verdict()` so that noise alone cannot fail a model;
- be **calibrated against its own null**, not against a convention. This is the
  one requirement that is easy to miss. Several conventional thresholds in this
  field misfire badly: the population stability index flags around 80% of
  unshifted 50-row batches at its usual 0.2 line, and screening features by
  accuracy scores 0.97 on pure noise when the event rate is 3%. If your
  statistic's null value depends on sample size, class balance, or whether it
  was estimated in sample, say so and handle it.

A check that blocks certification needs a test showing it fires on a case it
should catch **and** one showing it stays quiet on a case it should not.

## Development

```r
devtools::load_all()
devtools::test()
devtools::check()
```

Before opening a pull request:

- `styler::style_pkg()` — the package follows tidyverse style, no line over 100
  characters;
- `lintr::lint_package()` — clean;
- `spelling::spell_check_package()` — clean; the package is written in
  `en-GB`, and genuine technical terms go in `inst/WORDLIST`;
- `devtools::document()` if you touched roxygen comments.

`R CMD build` copies the working directory before applying `.Rbuildignore`, so
a deeply nested path under `.git` can break the build on Windows. If that
happens, `git pack-refs --all` resolves it without losing anything.

## Claims in documentation

If you state a figure in the documentation, the vignette or a paper, measure it
first and say where it came from. Most of the defects found in this package so
far were found by trying to write down a claim about it and then checking the
claim, rather than by writing more code.
