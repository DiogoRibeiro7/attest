# Read the entries of a ledger

Read the entries of a ledger

## Usage

``` r
ledger_entries(ledger)
```

## Arguments

- ledger:

  An
  [`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md).

## Value

A list of entries, oldest first. Empty if the file does not exist.

## See also

Other ledgers:
[`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md),
[`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md),
[`ledger_append()`](https://diogoribeiro7.github.io/attest/reference/ledger_append.md),
[`ledger_find()`](https://diogoribeiro7.github.io/attest/reference/ledger_find.md),
[`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)

## Examples

``` r
led <- attest_ledger(tempfile(fileext = ".ndjson"))
length(ledger_entries(led))
#> [1] 0
```
