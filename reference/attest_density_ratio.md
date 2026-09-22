# Estimate a covariate density ratio between calibration and new data

Fits a probabilistic classifier separating the calibration rows from the
incoming rows and converts its predictions into a likelihood ratio
\\w(x) = \mathrm{d}Q_X / \mathrm{d}P_X(x)\\, estimated as the odds
\\p(x) / (1 - p(x))\\ where \\p\\ is the probability a row came from the
new batch. This is the "classifier two-sample" estimator: an AUC near
0.5 means the two samples are indistinguishable and every weight is near
1.

## Usage

``` r
attest_density_ratio(calib_x, new_x, features, max_ratio = 100)
```

## Arguments

- calib_x:

  Data frame of calibration covariates.

- new_x:

  Data frame of incoming covariates, same columns.

- features:

  Character vector of columns to use.

- max_ratio:

  Weights are clipped to `[1 / max_ratio, max_ratio]`. An unclipped
  ratio can be enormous when the classifier separates the samples almost
  perfectly, which would let a handful of rows dominate the weighted
  quantile.

## Value

A list with `calib` and `new`, the weights for each set, and `auc`, the
in-sample area under the curve of the discriminating classifier.

## Details

Only a global constant separates the odds from the true ratio, and that
constant cancels in
[`attest_weighted_quantile()`](https://diogoribeiro7.github.io/attest/reference/attest_weighted_quantile.md),
so no calibration of the scale is required.

## See also

Other conformal checks:
[`attest_weighted_quantile()`](https://diogoribeiro7.github.io/attest/reference/attest_weighted_quantile.md),
[`conformal_split()`](https://diogoribeiro7.github.io/attest/reference/conformal_split.md)

Other shift checks:
[`attest_c2st()`](https://diogoribeiro7.github.io/attest/reference/attest_c2st.md),
[`shift_c2st()`](https://diogoribeiro7.github.io/attest/reference/shift_c2st.md),
[`shift_monitor()`](https://diogoribeiro7.github.io/attest/reference/shift_monitor.md)

## Examples

``` r
set.seed(1)
a <- data.frame(x = rnorm(300))
b <- data.frame(x = rnorm(300, 1))
w <- attest_density_ratio(a, b, "x")
round(w$auc, 2)
#> [1] 0.75
```
