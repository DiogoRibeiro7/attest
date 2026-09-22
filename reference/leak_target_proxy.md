# Leakage check: a single feature is a near-deterministic proxy of the target

For each feature, a one-variable model is fitted on the training set.
The statistic is the area under the curve for a binary outcome, mean
per-class recall for multiclass, and R-squared for regression. Any
feature above `threshold` fails the check.

## Usage

``` r
leak_target_proxy(threshold = 0.95, n_boot = 500)
```

## Arguments

- threshold:

  Maximum tolerated single-feature score: AUC for a binary outcome, mean
  per-class recall for multiclass, R-squared for regression.

- n_boot:

  Bootstrap replicates for the confidence interval on the strongest
  feature's score; `0` disables it and the point estimate decides.

## Value

An `attest_check`.

## Details

The statistic is deliberately not accuracy. A majority-class rule
already achieves the base rate, so on a rare outcome – a 3% claim rate,
say – accuracy makes every feature look like a near-perfect proxy and
the check refuses every model. All three statistics used here sit at
chance for a feature with no predictive power, however skewed the
outcome, and at one for a feature that reproduces it.

The reported statistic is the maximum score across features. It is given
a bootstrap confidence interval over training rows, so a feature that
merely looks strong in a small sample no longer fails the check
outright: the verdict is `"weak"` unless the whole interval sits above
`threshold`.

Bootstrapping is conditional on the fitted one-variable models – they
are fitted once, and resampling is applied to their per-row predictions
rather than refitting each replicate. This keeps the check affordable
and captures sampling noise in the score, but not the variability of the
fits themselves.

## See also

Other leakage checks:
[`leak_duplicates()`](https://diogoribeiro7.github.io/attest/reference/leak_duplicates.md),
[`leak_temporal()`](https://diogoribeiro7.github.io/attest/reference/leak_temporal.md)

## Examples

``` r
leak_target_proxy()
#> <attest_check> Target proxy leakage <leak_target_proxy> [pre, blocking]
# a stricter bar, with the interval disabled
leak_target_proxy(threshold = 0.9, n_boot = 0)
#> <attest_check> Target proxy leakage <leak_target_proxy> [pre, blocking]
```
