# Leakage check: exact duplicate rows across train and test

Leakage check: exact duplicate rows across train and test

## Usage

``` r
leak_duplicates(max_prop = 0)
```

## Arguments

- max_prop:

  Maximum tolerated proportion of test rows that are exact duplicates of
  training rows.

## Value

An `attest_check`.

## Details

Unlike
[`calib_ece()`](https://diogoribeiro7.github.io/attest/reference/calib_ece.md)
or
[`conformal_split()`](https://diogoribeiro7.github.io/attest/reference/conformal_split.md),
this check reports no confidence interval. Duplication is a census of
the rows you actually hold, not an estimate of a population quantity: if
a training row appears in the test set, it is there, and resampling
would only describe a hypothetical other dataset. The same reasoning
applies to
[`leak_temporal()`](https://diogoribeiro7.github.io/attest/reference/leak_temporal.md).

The default tolerates nothing, which is right when a duplicate row means
the same record reached both partitions. Be aware that on real data with
low-cardinality features some duplication is arithmetic rather than
leakage: two distinct subjects can share every recorded value. A motor
portfolio of 68,000 policies described by seven mixed rating factors
produces around 0.9% duplication with no leak present. The check reports
the count as well as the proportion so that `max_prop` can be set from
the data rather than guessed.

## See also

Other leakage checks:
[`leak_target_proxy()`](https://diogoribeiro7.github.io/attest/reference/leak_target_proxy.md),
[`leak_temporal()`](https://diogoribeiro7.github.io/attest/reference/leak_temporal.md)

## Examples

``` r
leak_duplicates()
#> <attest_check> Duplicate row leakage <leak_duplicates> [pre, blocking]
# tolerate a small overlap
leak_duplicates(max_prop = 0.01)
#> <attest_check> Duplicate row leakage <leak_duplicates> [pre, blocking]
```
