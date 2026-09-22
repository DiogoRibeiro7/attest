# Build a portable manifest for an attested model

A manifest is the certificate reduced to the facts that identify it: the
three hashes, what was fitted, and the environment it was fitted in. It
is plain data, so it can be written to a file, sent to someone who does
not have the model, and compared later.

## Usage

``` r
attest_manifest(x)
```

## Arguments

- x:

  An `attested_model`.

## Value

A named list.

## See also

Other certificates:
[`certificate()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)

Other ledgers:
[`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md),
[`ledger_append()`](https://diogoribeiro7.github.io/attest/reference/ledger_append.md),
[`ledger_entries()`](https://diogoribeiro7.github.io/attest/reference/ledger_entries.md),
[`ledger_find()`](https://diogoribeiro7.github.io/attest/reference/ledger_find.md),
[`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
str(attest_manifest(m))
#> List of 18
#>  $ certificate_id: chr "b897d5d357d5"
#>  $ issued        : chr "2026-09-22 21:59:21"
#>  $ status        : chr "valid"
#>  $ hash_data     : chr "2146f198f0f75f663b4e8087b3332de67b86a3f690f37d35f6238698f7dad6ae"
#>  $ hash_spec     : chr "e6bac019dc632915e713be1f6c241378d4431bfeb601f8d850be80dcfa9fb134"
#>  $ hash_model    : chr "8efc81e42431947a1fb27b540c21be70596545bf24d88b87f5e468de1b571fac"
#>  $ engine        : chr "glm"
#>  $ split         : chr "split_random"
#>  $ task          : chr "classification"
#>  $ outcome       : chr "y"
#>  $ features      : chr "x1,x2"
#>  $ n_train       : int 640
#>  $ n_calib       : int 160
#>  $ n_test        : int 200
#>  $ waived        : chr ""
#>  $ attest_version: chr "0.1.0"
#>  $ r_version     : chr "4.6.1"
#>  $ platform      : chr "x86_64-pc-linux-gnu"
```
