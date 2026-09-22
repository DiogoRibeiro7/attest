# Decide a check verdict from an interval and a threshold

Implements the rule that a check fails only when the whole confidence
interval clears the threshold, so that noise alone cannot fail a check.
When the interval straddles the threshold the verdict is `"weak"`: the
evidence does not settle the question either way.

## Usage

``` r
attest_verdict(statistic, ci, threshold, direction = c("at_most", "at_least"))
```

## Arguments

- statistic:

  The point estimate.

- ci:

  Confidence interval for `statistic`, length 2.

- threshold:

  The threshold to compare against.

- direction:

  `"at_most"` when the statistic should not exceed the threshold (ECE,
  PSI), `"at_least"` when it should not fall below it (coverage).

## Value

One of `"pass"`, `"weak"`, `"fail"`.

## Details

If `ci` is `c(NA, NA)` the point estimate decides, and `"weak"` is never
returned.

## See also

Other checks:
[`attest_boot()`](https://diogoribeiro7.github.io/attest/reference/attest_boot.md),
[`attest_result()`](https://diogoribeiro7.github.io/attest/reference/attest_result.md),
[`imbalance_report()`](https://diogoribeiro7.github.io/attest/reference/imbalance_report.md),
[`new_check()`](https://diogoribeiro7.github.io/attest/reference/new_check.md)

## Examples

``` r
attest_verdict(0.04, c(0.02, 0.09), threshold = 0.05, direction = "at_most")
#> [1] "weak"
attest_verdict(0.04, c(0.02, 0.045), threshold = 0.05, direction = "at_most")
#> [1] "pass"
```
