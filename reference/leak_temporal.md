# Leakage check: test rows must not precede training rows in time

Leakage check: test rows must not precede training rows in time

## Usage

``` r
leak_temporal(time, max_prop = 0)
```

## Arguments

- time:

  Name of the time column.

- max_prop:

  Maximum tolerated proportion of test rows dated before the last
  training row.

## Value

An `attest_check`.

## See also

Other leakage checks:
[`leak_duplicates()`](https://diogoribeiro7.github.io/attest/reference/leak_duplicates.md),
[`leak_target_proxy()`](https://diogoribeiro7.github.io/attest/reference/leak_target_proxy.md)

## Examples

``` r
leak_temporal("order_date")
#> <attest_check> Temporal leakage <leak_temporal> [pre, blocking]
```
