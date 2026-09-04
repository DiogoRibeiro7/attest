# attest

> Fail-closed machine learning: models that carry their own proof of validity.

<!-- badges: start -->
[![R-CMD-check](https://github.com/DiogoRibeiro7/attest/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/DiogoRibeiro7/attest/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

Every modelling function in R will happily return a number. `attest` makes
that the hard path. A model fitted with `attest_fit()` cannot be reported or
deployed without a **certificate**: leakage, calibration, conformal coverage
and distribution-shift checks that run at fit time and are stored inside the
object, hash-bound to the model. Predictions are never bare numbers — they
come with an interval and a validity status, and are **refused** when the
input falls outside the certified support.

The contract:

1. No certificate, no predictions.
2. A prediction is a value **and** a guarantee **and** a status.
3. Failure means refusal by default. You can waive a check, but you must sign
   a reason, and it is printed on every report.
4. The certificate is bound to the model by hash. Change the model, break the
   seal.

## Installation

```r
# install.packages("pak")
pak::pak("DiogoRibeiro7/attest")
```

## Example

```r
library(attest)

set.seed(1)
d <- data.frame(x1 = rnorm(2000), x2 = rnorm(2000))
d$y <- factor(rbinom(2000, 1, plogis(0.8 * d$x1 - 0.5 * d$x2)))

m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm())
#> ✔ leak_duplicates      pass        0.0% of test rows duplicate a training row
#> ✔ leak_target_proxy    pass        max single-feature score 0.627 [0.602, 0.653]
#> i imbalance_report     info        minority/majority ratio 0.960 (0=627, 1=653)
#> ? calib_ece            weak        ECE = 0.059 [0.043, 0.107] (max 0.100)
#> ? conformal_split      weak        empirical coverage 0.892 [0.863, 0.922] (target 0.900)
#> i shift_monitor        info        baseline stored
#> ! inconclusive: calib_ece, conformal_split -- interval straddles the threshold
#> ℹ Certificate 5df55092f486 issued 2026-09-04 21:20:05 UTC (valid)

nd <- d[1:3, ]; nd$x1[1] <- 50
predict(m, nd)
#> # attested_prediction: 3 rows, certificate 5df55092f486
#> valid: 2 | flagged: 0 | refused: 1
#>    .pred .set  .status .shift .reason
#> 1 NA     <NA>  refused    0.5  outside training support: x1
#> 2  0.768 {1}   valid      0.5  NA
#> 3  0.210 {0}   valid      0.5  NA

report(m, "model_card.md")   # rendered from the certificate, never hand-written
```

Two checks come back `weak` rather than `pass`: at 2,000 rows the confidence
intervals for ECE and coverage straddle their thresholds, so the evidence does
not settle the question either way. A check fails only when its whole interval
clears the line, so noise alone cannot fail a model -- but "we could not tell"
is recorded as such rather than quietly counted as a pass. Use
`attest_spec(strict = TRUE)` to treat an inconclusive check as a failure.

```r
```

A leaky feature at fit time:

```r
d$leak <- as.integer(d$y)
attest_fit(attest_spec(), y ~ x1 + leak, d, engine_glm())
#> ✖ leak_target_proxy    fail        proxy features: leak
#> Error: refused to issue certificate (on_fail = "refuse")
#> ℹ blocking checks failed: leak_target_proxy
#> ℹ to proceed anyway: attest_fit(..., waive = <check id>, reason = "...")
```

## What is in the box (v0.1)

| | |
|---|---|
| Tasks | binary classification, regression |
| Engines | `engine_glm()`, `engine_ranger()`; extend via `engine_fit()` / `engine_predict()` methods |
| Splits | `split_random()`, `split_grouped()`, `split_temporal()` |
| Checks | `leak_duplicates()`, `leak_target_proxy()`, `leak_temporal()`, `imbalance_report()`, `calib_ece()`, `conformal_split()`, `shift_monitor()`; extend via `new_check()` |
| Outputs | `certificate()`, `verify()`, `is_sealed()`, `report()`, `unseal()` |

## What it does not promise

- Conformal coverage is **marginal**: honest on average over exchangeable
  data, not for any individual row.
- PSI is a crude drift detector. It is shipped because it is interpretable;
  other two-sample tests are on the roadmap.
- A determined user can set `on_fail = "warn"`. The package cannot stop you
  from lying; it only makes sure the lie is signed.

## Roadmap

Multiclass; survival outcomes with conformal intervals; `parsnip` and `mlr3`
engine adapters; HTML model cards; classifier two-sample shift tests.

## Citation

Ribeiro, D. (2026). *attest: fail-closed machine learning in R*. R package
version 0.1.0. https://github.com/DiogoRibeiro7/attest
