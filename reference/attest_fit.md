# Fit a model and issue a certificate

Fit a model and issue a certificate

## Usage

``` r
attest_fit(
  spec,
  formula,
  data,
  engine = engine_glm(),
  waive = character(0),
  reason = NULL,
  quiet = FALSE
)
```

## Arguments

- spec:

  An
  [`attest_spec()`](https://diogoribeiro7.github.io/attest/reference/attest_spec.md).

- formula:

  Model formula. The outcome sets the task: numeric gives regression, a
  logical or two-level factor gives binary classification, and a factor
  with more than two levels gives multiclass.

- data:

  A data frame.

- engine:

  An engine, see
  [engines](https://diogoribeiro7.github.io/attest/reference/engines.md).

- waive:

  Character vector of check ids to waive. Every waiver requires a
  `reason`.

- reason:

  Character string explaining the waiver. Stored in the certificate and
  printed in every report.

- quiet:

  Suppress progress output.

## Value

An object of class `attested_model`.

## See also

Other fitting:
[`attest_spec()`](https://diogoribeiro7.github.io/attest/reference/attest_spec.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(2000), x2 = rnorm(2000))
d$y <- factor(rbinom(2000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
certificate(m)
#> 
#> ── Certificate ca4e2a61f60d ──
#> 
#> issued 2026-09-22 21:59:20 UTC | status valid | on_fail "refuse"
#> task classification | engine glm | split split_random | n = 1280/320/400
#> (train/calib/test)
#> ✔ Duplicate row leakage        pass        0.00% of test rows duplicate a training row (0 of 400)
#> ✔ Target proxy leakage         pass        max single-feature score 0.715 [0.690, 0.741]
#> i Class imbalance              info        minority/majority ratio 0.925 (0=665, 1=615)
#> ? Calibration error            weak        ECE = 0.077 [0.066, 0.132] (max 0.100)
#> ? Conformal coverage           weak        empirical coverage 0.873 [0.840, 0.905] (target 0.900)
#> i Population stability shift   info        baseline stored
predict(m, d[1:3, ])
#> # attested_prediction: 3 rows, certificate ca4e2a61f60d
#> valid: 3 | flagged: 0 | refused: 0
#> # A tibble: 3 × 5
#>    .pred .set  .status .shift .reason
#> *  <dbl> <chr> <chr>    <dbl> <chr>  
#> 1 0.569  {0,1} valid    0.398 NA     
#> 2 0.884  {1}   valid    0.828 NA     
#> 3 0.0829 {0}   valid    0.783 NA     
```
