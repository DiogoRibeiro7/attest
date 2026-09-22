# Build an attestation specification

Build an attestation specification

## Usage

``` r
attest_spec(
  split = split_random(),
  checks = default_checks(),
  on_fail = c("refuse", "flag", "warn"),
  strict = FALSE
)

default_checks()
```

## Arguments

- split:

  A split strategy, see
  [splits](https://diogoribeiro7.github.io/attest/reference/splits.md).

- checks:

  A list of checks, see
  [`new_check()`](https://diogoribeiro7.github.io/attest/reference/new_check.md).
  Defaults to the standard set: duplicates, target proxy, imbalance
  report, ECE, split conformal and a PSI shift monitor.

- on_fail:

  What to do when a blocking check fails: `"refuse"` (default; no
  certificate is issued and fitting errors), `"flag"` (certificate is
  issued but marked as failed) or `"warn"`.

- strict:

  How to treat a `"weak"` check, where the statistic's confidence
  interval straddles its threshold. `FALSE` (default) treats it as a
  pass: a check fails only on confident violation. `TRUE` treats it as a
  failure, so inconclusive evidence blocks certification. Set it when
  scarce data must not buy a certificate by widening intervals.

## Value

An object of class `attest_spec`.

## See also

Other fitting:
[`attest_fit()`](https://diogoribeiro7.github.io/attest/reference/attest_fit.md)

## Examples

``` r
spec <- attest_spec(split_random(0.25), on_fail = "flag")
spec
#> 
#> ── attest_spec 
#> split: split_random; on_fail: "flag"
#> • Duplicate row leakage leak_duplicates (pre, blocking)
#> • Target proxy leakage leak_target_proxy (pre, blocking)
#> • Class imbalance imbalance_report (pre)
#> • Calibration error calib_ece (post, blocking)
#> • Conformal coverage conformal_split (post, blocking)
#> • Population stability shift shift_monitor (post)
```
