# Bootstrap a confidence interval for a check statistic

Resamples row indices with replacement and recomputes the statistic,
giving a percentile interval. Checks use this so that a threshold
comparison accounts for sampling noise rather than resting on a point
estimate.

## Usage

``` r
attest_boot(stat, n, n_boot = 1000, conf = 0.95)
```

## Arguments

- stat:

  Function of one argument, an integer vector of row indices, returning
  a single number.

- n:

  Number of rows to resample from.

- n_boot:

  Number of bootstrap replicates. `0` disables estimation and returns
  `c(NA, NA)`.

- conf:

  Confidence level.

## Value

A numeric vector of length 2.

## See also

Other checks:
[`attest_result()`](https://diogoribeiro7.github.io/attest/reference/attest_result.md),
[`attest_verdict()`](https://diogoribeiro7.github.io/attest/reference/attest_verdict.md),
[`imbalance_report()`](https://diogoribeiro7.github.io/attest/reference/imbalance_report.md),
[`new_check()`](https://diogoribeiro7.github.io/attest/reference/new_check.md)

## Examples

``` r
y <- rbinom(200, 1, 0.3)
attest_boot(function(i) mean(y[i]), n = length(y), n_boot = 200)
#> [1] 0.259875 0.375125
```
