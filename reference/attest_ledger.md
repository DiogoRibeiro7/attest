# An append-only ledger of issued certificates

Records every certificate a project issues in a newline-delimited JSON
file. Each entry carries the digest of the entry before it, so the file
is a chain: altering or removing any earlier record breaks every digest
after it, and
[`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)
reports where.

## Usage

``` r
attest_ledger(path, key = NULL)
```

## Arguments

- path:

  Path to the ledger file. Created on first append.

- key:

  Optional secret key. When given, entries are sealed with an HMAC and
  the same key is needed to verify them.

## Value

An object of class `attest_ledger`.

## Details

Be precise about what the seal proves, because the two modes differ in
kind rather than in degree.

Without `key`, entries are sealed with a plain SHA-256 digest. Because
each entry also carries the previous entry's digest, editing or deleting
a single record is caught: every later entry still points at the digest
the record used to have. What a plain digest does **not** withstand is
someone rewriting the whole chain, which anyone with the package can do.
Treat it as a tamper-evident log against accident, corruption and casual
editing – not as a signature.

With a secret `key`, entries are sealed with an HMAC, and a rewritten
chain cannot be resealed without the key. That is a real integrity
guarantee, and it rests entirely on the key: anyone holding it can
rewrite the ledger undetectably. Keep it out of the ledger, out of the
repository and out of the script that writes it.

The ledger records that a certificate was issued and what it covered. It
is not a guarantee that the model behind it still exists or is unchanged
–
[`verify()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
compares a model in hand against the record.

Appending reads the file and rewrites one line, which is not safe
against two processes writing at once.

## See also

Other ledgers:
[`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md),
[`ledger_append()`](https://diogoribeiro7.github.io/attest/reference/ledger_append.md),
[`ledger_entries()`](https://diogoribeiro7.github.io/attest/reference/ledger_entries.md),
[`ledger_find()`](https://diogoribeiro7.github.io/attest/reference/ledger_find.md),
[`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)

## Examples

``` r
led <- attest_ledger(tempfile(fileext = ".ndjson"))
led
#> <attest_ledger> /tmp/RtmpizheUw/file199514dbbe41.ndjson -- 0 entries
```
