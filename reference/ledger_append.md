# Append a certificate to a ledger

Append a certificate to a ledger

## Usage

``` r
ledger_append(ledger, x, note = NULL)
```

## Arguments

- ledger:

  An
  [`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md).

- x:

  An `attested_model`.

- note:

  Optional free text stored with the entry, such as the run or pipeline
  that produced the model.

## Value

The ledger, invisibly.

## See also

Other ledgers:
[`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md),
[`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md),
[`ledger_entries()`](https://diogoribeiro7.github.io/attest/reference/ledger_entries.md),
[`ledger_find()`](https://diogoribeiro7.github.io/attest/reference/ledger_find.md),
[`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
led <- attest_ledger(tempfile(fileext = ".ndjson"))
ledger_append(led, m, note = "nightly run")
nrow(ledger_entries(led))
#> NULL
```
