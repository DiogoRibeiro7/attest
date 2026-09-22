# Split strategies

A split returns integer row indices for `train`, `calib` and `test`.

## Usage

``` r
split_random(prop = 0.2, calib = 0.2)

split_grouped(group, prop = 0.2, calib = 0.2)

split_temporal(time, prop = 0.2, calib = 0.2)
```

## Arguments

- prop:

  Proportion of rows held out for testing.

- calib:

  Proportion of the remaining rows held out for conformal calibration.

- group:

  Name of a grouping column; whole groups are assigned to one partition.

- time:

  Name of a time column; the latest rows become the test set.

## Value

An object of class `attest_split`.

## Examples

``` r
split_random(prop = 0.25, calib = 0.2)
#> <attest_split> split_random
split_grouped("customer_id")
#> <attest_split> split_grouped
split_temporal("order_date", prop = 0.3)
#> <attest_split> split_temporal
```
