# Engine adapters

An engine is a thin adapter around a modelling function. Three generics
define the interface:
[`engine_fit()`](https://diogoribeiro7.github.io/attest/reference/engine_fit.md)
and
[`engine_predict()`](https://diogoribeiro7.github.io/attest/reference/engine_predict.md).

## Usage

``` r
engine_glm(...)

engine_ranger(...)
```

## Arguments

- ...:

  Arguments passed to the underlying fitting function.

## Value

An object of class `attest_engine`.

## See also

Other engines:
[`engine_fit()`](https://diogoribeiro7.github.io/attest/reference/engine_fit.md),
[`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md),
[`engine_predict()`](https://diogoribeiro7.github.io/attest/reference/engine_predict.md)

## Examples

``` r
engine_glm()
#> <attest_engine> glm
engine_glm(weights = NULL)
#> <attest_engine> glm
```
