# Fit a model with an engine

Fit a model with an engine

## Usage

``` r
engine_fit(engine, formula, data, task)
```

## Arguments

- engine:

  An `attest_engine`.

- formula:

  Model formula.

- data:

  Training data.

- task:

  `"classification"` or `"regression"`.

## Value

A fitted object.

## See also

Other engines:
[`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md),
[`engine_predict()`](https://diogoribeiro7.github.io/attest/reference/engine_predict.md),
[`engines`](https://diogoribeiro7.github.io/attest/reference/engines.md)

## Examples

``` r
set.seed(1)
d <- data.frame(x = rnorm(400))
d$y <- factor(rbinom(400, 1, plogis(d$x)))
fit <- engine_fit(engine_glm(), y ~ x, d, "classification")
class(fit)
#> [1] "glm" "lm" 
```
