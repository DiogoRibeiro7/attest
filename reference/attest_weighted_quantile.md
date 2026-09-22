# Weighted conformal quantile

The quantile of Tibshirani et al. (2019) for conformal prediction under
covariate shift. Calibration scores are weighted by their density ratio
and augmented with a point mass at infinity carrying the test point's
own weight, so a test point unlike anything in the calibration set
receives an infinite quantile rather than a falsely narrow one.

## Usage

``` r
attest_weighted_quantile(scores, w_calib, w_new, alpha = 0.1)
```

## Arguments

- scores:

  Numeric calibration scores.

- w_calib:

  Weights for the calibration scores, same length.

- w_new:

  Weights for the points being predicted, one per row.

- alpha:

  Miscoverage level; the quantile targets `1 - alpha`.

## Value

A numeric vector the length of `w_new`, possibly containing `Inf`.

## Details

With every weight equal to 1 this reduces exactly to the ordinary split
conformal quantile, so enabling weighting costs nothing when nothing has
moved.

Four limits are worth stating plainly.

It addresses **covariate shift only**. The guarantee assumes the
conditional distribution of the outcome given the covariates is
unchanged and only the covariate distribution has moved. If the
relationship itself has drifted – label shift, concept drift, a changed
measurement process – reweighting corrects nothing, and can be worse
than useless by returning intervals that look adjusted.

The guarantee assumes the density ratio is **known exactly**. In
practice it is estimated from a finite batch by
[`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md),
so coverage is approximate rather than guaranteed, and the error grows
as the estimate gets harder.

Under strong shift the weighted calibration set has a small **effective
sample size**: a few heavily weighted scores carry the quantile, which
makes it noisy and generally conservative. Expect over-coverage and wide
intervals well before the method fails outright.

The quantile becomes **infinite** when a point's own weight is large
relative to the calibration set. That is the honest answer – no finite
interval is justified – and
[`predict.attested_model()`](https://diogoribeiro7.github.io/attest/reference/predict.attested_model.md)
refuses such rows rather than reporting an unbounded one.

## References

Tibshirani, R. J., Barber, R. F., Candes, E. J. and Ramdas, A. (2019)
Conformal Prediction Under Covariate Shift. *Advances in Neural
Information Processing Systems*.

## See also

Other conformal checks:
[`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md),
[`conformal_split()`](https://diogoribeiro7.github.io/attest/reference/conformal_split.md)

## Examples

``` r
s <- c(0.1, 0.2, 0.3, 0.4, 0.9)
attest_weighted_quantile(s, rep(1, 5), c(1, 5), alpha = 0.2)
#> [1] 0.9 Inf
```
