# Predict from an engine-fitted object

Predict from an engine-fitted object

## Usage

``` r
engine_predict(
  engine,
  object,
  newdata,
  type = c("prob", "numeric", "prob_matrix")
)
```

## Arguments

- engine:

  An `attest_engine`.

- object:

  The fitted object.

- newdata:

  Data to predict on.

- type:

  `"prob"` (probability of the second factor level), `"numeric"`, or
  `"prob_matrix"` (one column per class, in level order, for multiclass
  outcomes).

## Value

A numeric vector.

## See also

Other engines:
[`engine_fit()`](https://diogoribeiro7.github.io/attest/reference/engine_fit.md),
[`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md),
[`engines`](https://diogoribeiro7.github.io/attest/reference/engines.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x = rnorm(400))
d$y <- factor(rbinom(400, 1, plogis(d$x)))
fit <- engine_fit(engine_glm(), y ~ x, d, "classification")
head(engine_predict(engine_glm(), fit, d, type = "prob"))
#> [1] 0.2926876 0.5275159 0.2425683 0.8629169 0.5717243 0.2459973
```
