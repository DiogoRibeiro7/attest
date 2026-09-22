# Predict with validity status

Returns an `attested_prediction`: a tibble with `.pred`, an interval
(`.lower`/`.upper` for regression, `.set` for classification), a
`.status` of `"valid"`, `"flagged"` or `"refused"`, a row-level `.shift`
score and a `.reason`. Refused rows have `NA` predictions unless
`enforce = FALSE`.

## Usage

``` r
# S3 method for class 'attested_model'
predict(object, newdata, enforce = TRUE, ...)
```

## Arguments

- object:

  An `attested_model`.

- newdata:

  Data to predict on.

- enforce:

  If `FALSE`, refused rows still receive predictions (status is kept).
  Overriding the contract is recorded in the returned object's
  `"enforced"` attribute.

- ...:

  Unused.

## Value

A tibble of class `attested_prediction`.

## Details

`.shift` is the row's Mahalanobis position within the joint training
distribution, on a chi-square probability scale: 0.5 is a typical row
and 0.99 means further from the centre than 99% of the training data.
Because it uses the joint structure it catches a row that is
unremarkable on every feature taken alone but implausible in
combination, which a per-feature tail measure cannot. It falls back to
the share of features in the tails when the model has no numeric
features to form a covariance from.

When the model was fitted with `conformal_split(weighted = TRUE)` the
interval is not fixed. Calibration scores are reweighted by an estimated
covariate density ratio between the calibration set and this batch, so
each row gets its own quantile and intervals widen on drifted input. The
estimated ratio is returned in a `.weight` column.

`.status` keeps its meaning throughout: `"flagged"` still reports that
the batch moved, not that the interval changed. A row whose reweighted
quantile is infinite – the calibration set holds no comparable evidence
– is refused, with reason `"no conformal evidence after reweighting"`.

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
predict(m, d[1:3, ])
#> # attested_prediction: 3 rows, certificate b897d5d357d5
#> valid: 3 | flagged: 0 | refused: 0
#> # A tibble: 3 × 5
#>   .pred .set  .status .shift .reason
#> * <dbl> <chr> <chr>    <dbl> <chr>  
#> 1 0.180 {0}   valid    0.572 NA     
#> 2 0.340 {0,1} valid    0.464 NA     
#> 3 0.499 {0,1} valid    0.471 NA     
# a row outside the certified support is refused
nd <- d[1:2, ]
nd$x1[1] <- 50
predict(m, nd)
#> # attested_prediction: 2 rows, certificate b897d5d357d5
#> valid: 1 | flagged: 0 | refused: 1
#> # A tibble: 2 × 5
#>    .pred .set  .status .shift .reason                     
#> *  <dbl> <chr> <chr>    <dbl> <chr>                       
#> 1 NA     NA    refused  1     outside training support: x1
#> 2  0.340 {0,1} valid    0.464 NA                          
```
