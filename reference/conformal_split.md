# Coverage check: split conformal prediction

Calibrates a nonconformity quantile on the held-out calibration set and
verifies empirical coverage on the test set. For regression the score is
the absolute residual and predictions carry an interval; for binary
classification the score is `1 - p(true class)` and predictions carry a
label set.

## Usage

``` r
conformal_split(alpha = 0.1, tolerance = 0.03, n_boot = 1000, weighted = FALSE)
```

## Arguments

- alpha:

  Miscoverage level; target coverage is `1 - alpha`.

- tolerance:

  Tolerated shortfall of empirical test coverage below `1 - alpha`
  before the check fails.

- n_boot:

  Bootstrap replicates for the coverage confidence interval; `0`
  disables it and the point estimate decides.

- weighted:

  If `TRUE`, store the calibration scores and covariates in the
  certificate so that
  [`predict.attested_model()`](https://diogoribeiro7.github.io/attest/reference/predict.attested_model.md)
  can reweight them by an estimated covariate density ratio, widening
  intervals on batches that have drifted. See
  [`attest_weighted_quantile()`](https://diogoribeiro7.github.io/attest/reference/attest_weighted_quantile.md)
  for the guarantee this targets and its limits. The stored calibration
  set is what makes the certificate larger, so this is off by default.

## Value

An `attest_check`.

## Details

Empirical coverage is a sample statistic and scatters around its target,
so it is reported with a bootstrap confidence interval over test rows.
The check fails only when the whole interval sits below
`1 - alpha - tolerance`, and is `"weak"` when the interval straddles
that line.

The interval reflects sampling noise in the *test* set only. The
calibration quantile `q` is treated as fixed, so the interval
understates total uncertainty when the calibration set is small.

## See also

Other conformal checks:
[`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md),
[`attest_weighted_quantile()`](https://diogoribeiro7.github.io/attest/reference/attest_weighted_quantile.md)

## Examples

``` r
conformal_split()
#> <attest_check> Conformal coverage <conformal_split> [post, blocking]
# 95% target coverage
conformal_split(alpha = 0.05)
#> <attest_check> Conformal coverage <conformal_split> [post, blocking]
```
