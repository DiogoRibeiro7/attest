# Find the ledger entry for a model

Find the ledger entry for a model

## Usage

``` r
ledger_find(ledger, x)
```

## Arguments

- ledger:

  An
  [`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md).

- x:

  An `attested_model`, or a certificate id.

## Value

The matching entry, or `NULL`.

## See also

Other ledgers:
[`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md),
[`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md),
[`ledger_append()`](https://diogoribeiro7.github.io/attest/reference/ledger_append.md),
[`ledger_entries()`](https://diogoribeiro7.github.io/attest/reference/ledger_entries.md),
[`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
led <- attest_ledger(tempfile(fileext = ".ndjson"))
ledger_append(led, m)
ledger_find(led, m)$certificate_id
#> [1] "b897d5d357d5"
```
