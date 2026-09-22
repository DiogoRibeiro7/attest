# Calibration check: expected calibration error on the test set

The ECE is a sample statistic, so it is reported with a bootstrap
confidence interval over test rows and the verdict follows
[`attest_verdict()`](https://diogoribeiro7.github.io/attest/reference/attest_verdict.md):
the check fails only when the whole interval sits above `max`, and is
`"weak"` when the interval straddles it.

## Usage

``` r
calib_ece(max = 0.1, bins = 10, n_boot = 1000)
```

## Arguments

- max:

  Maximum tolerated ECE.

- bins:

  Number of equal-width probability bins.

- n_boot:

  Bootstrap replicates for the confidence interval; `0` disables it and
  the point estimate decides.

## Value

An `attest_check`.

## Examples

``` r
calib_ece()
#> <attest_check> Calibration error <calib_ece> [post, blocking]
calib_ece(max = 0.05, bins = 20)
#> <attest_check> Calibration error <calib_ece> [post, blocking]
```
