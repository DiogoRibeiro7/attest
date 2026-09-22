# Fit any parsnip model under a certificate

Wraps a parsnip model specification, so anything parsnip can fit –
`boost_tree()` on xgboost, `linear_reg()` on glmnet, `rand_forest()` on
ranger, and the rest – can be certified without writing an adapter for
each.

## Usage

``` r
engine_parsnip(spec)
```

## Arguments

- spec:

  A parsnip `model_spec`, such as
  [`parsnip::logistic_reg()`](https://parsnip.tidymodels.org/reference/logistic_reg.html).

## Value

An object of class `attest_engine`.

## Details

The specification's mode is set from the task inferred by
[`attest_fit()`](https://diogoribeiro7.github.io/attest/reference/attest_fit.md),
so the usual `set_mode()` call is unnecessary. A mode that contradicts
the outcome is an error rather than a silent correction.

The certificate records the specification rather than the bare word
`"parsnip"`, as `parsnip:<model>/<engine>` – for example
`parsnip:boost_tree/xgboost` – so a model card says what was actually
fitted.

attest needs a probability for the second outcome level, which parsnip
supplies through `type = "prob"`. An engine offering no probabilities
cannot be calibrated or given conformal label sets, and is rejected at
fit time rather than issuing a certificate whose checks mean nothing.

## See also

Other engines:
[`engine_fit()`](https://diogoribeiro7.github.io/attest/reference/engine_fit.md),
[`engine_predict()`](https://diogoribeiro7.github.io/attest/reference/engine_predict.md),
[`engines`](https://diogoribeiro7.github.io/attest/reference/engines.md)

## Examples

``` r
if (requireNamespace("parsnip", quietly = TRUE)) {
  engine_parsnip(parsnip::logistic_reg())
}
#> <attest_engine> parsnip:logistic_reg/glm
```
