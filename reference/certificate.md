# Inspect and verify certificates

Inspect and verify certificates

## Usage

``` r
certificate(x)

is_sealed(x)

verify(x, data = NULL, ledger = NULL)

unseal(x)
```

## Arguments

- x:

  An `attested_model`.

- data:

  Training data used to fit the model, for hash verification.

- ledger:

  An optional
  [`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md).
  When given, `verify()` also checks that this certificate was recorded,
  that its hashes match the record, and that the ledger chain is intact.

## Value

`certificate()` returns the certificate; `is_sealed()` a logical;
`verify()` a logical with attribute `"diff"` listing what changed;
`unseal()` the raw engine object.

## See also

Other certificates:
[`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
certificate(m)
#> 
#> ── Certificate b897d5d357d5 ──
#> 
#> issued 2026-09-22 22:06:45 UTC | status valid | on_fail "refuse"
#> task classification | engine glm | split split_random | n = 640/160/200
#> (train/calib/test)
#> ✔ Duplicate row leakage        pass        0.00% of test rows duplicate a training row (0 of 200)
#> ✔ Target proxy leakage         pass        max single-feature score 0.725 [0.692, 0.764]
#> i Class imbalance              info        minority/majority ratio 0.877 (0=299, 1=341)
#> ? Calibration error            weak        ECE = 0.053 [0.052, 0.130] (max 0.100)
#> ✔ Conformal coverage           pass        empirical coverage 0.945 [0.915, 0.970] (target 0.900)
#> i Population stability shift   info        baseline stored
is_sealed(m)
#> [1] TRUE
verify(m)
#> [1] TRUE
#> attr(,"diff")
#> character(0)
class(unseal(m))
#> [1] "glm" "lm" 
```
