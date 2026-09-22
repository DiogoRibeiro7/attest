# Verify the integrity of a ledger chain

Recomputes each entry's digest and checks that it carries the digest of
the entry before it. An entry that has been altered fails on its own
digest; an entry that has been removed or reordered breaks the link in
the entry that followed it.

## Usage

``` r
ledger_verify(ledger)
```

## Arguments

- ledger:

  An
  [`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md).

## Value

A logical, `TRUE` when the chain is intact, with attribute `"problems"`
describing any breaks.

## See also

Other ledgers:
[`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md),
[`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md),
[`ledger_append()`](https://diogoribeiro7.github.io/attest/reference/ledger_append.md),
[`ledger_entries()`](https://diogoribeiro7.github.io/attest/reference/ledger_entries.md),
[`ledger_find()`](https://diogoribeiro7.github.io/attest/reference/ledger_find.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
led <- attest_ledger(tempfile(fileext = ".ndjson"))
ledger_append(led, m)
ledger_verify(led)
#> [1] TRUE
#> attr(,"problems")
#> character(0)
#> attr(,"n")
#> [1] 1
```
