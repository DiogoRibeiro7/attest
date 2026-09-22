# Shift monitor: population stability index baseline

Stores training-set bin edges and frequencies per feature. At prediction
time the batch PSI is computed per feature; batches with any feature
above `threshold` are flagged. Rows with a numeric feature outside the
training support (widened by `support_tol` times the range) or with an
unseen factor level are refused.

## Usage

``` r
shift_monitor(
  threshold = 0.2,
  bins = 10,
  support_tol = 0.05,
  min_batch = 50,
  n_boot = 500,
  conf = 0.95
)
```

## Arguments

- threshold:

  PSI above which a batch is flagged.

- bins:

  Number of quantile bins for numeric features.

- support_tol:

  Relative widening of the training range for the support check.

- min_batch:

  Minimum number of rows in a prediction batch for the batch PSI to be
  computed; smaller batches are only subject to the support check.

- n_boot:

  Replicates used at prediction time to calibrate the flag against the
  null distribution of PSI at the incoming batch size. `0` disables the
  calibration and compares against `threshold` alone.

- conf:

  Family-wise confidence for the null calibration. The per-feature
  quantile is Bonferroni-adjusted by the number of features, so `0.95`
  means roughly a 5% chance that an unshifted *batch* raises any flag,
  rather than 5% per feature.

## Value

An `attest_check`.

## Details

PSI is biased upward in small batches. With the default ten bins, a
batch of 50 rows drawn from the *training distribution itself* has a
median PSI of about 0.2 – the conventional flag threshold – so a fixed
threshold flags roughly half of all healthy small batches.

Rather than compare against a fixed line, this check simulates the null
at prediction time: batches of the observed size are drawn from the
stored training frequencies, and a feature is flagged only when its PSI
exceeds both `threshold` and the upper tail of that null. A flag
therefore means "more movement than this batch size produces by chance,
and larger than the effect size we care about".

Note the contrast with
[`calib_ece()`](https://diogoribeiro7.github.io/attest/reference/calib_ece.md)
and
[`conformal_split()`](https://diogoribeiro7.github.io/attest/reference/conformal_split.md),
which bootstrap *their own estimate* and compare the interval to an
absolute target. That works there because those estimators are roughly
unbiased for a fixed quantity. It does not work for PSI, whose noise
floor depends on the batch size, so the null is simulated instead of the
estimate resampled.

Sampling from the baseline multinomial costs `O(n_boot * bins)` and is
independent of batch size, so the calibration does not scale with the
data being predicted.

The two bars serve different purposes and the larger one governs. In
small batches the simulated null dominates and suppresses noise; in
large batches the null falls near zero and `threshold` dominates, acting
as an effect-size floor. A consequence is that a real but subtle shift
is not flagged however many rows you have, because `threshold` declares
it too small to matter. If you predict in large batches and want subtle
movement reported, lower `threshold` – the null calibration will still
hold the false-positive rate.

## See also

Other shift checks:
[`attest_c2st()`](https://diogoribeiro7.github.io/attest/reference/attest_c2st.md),
[`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md),
[`shift_c2st()`](https://diogoribeiro7.github.io/attest/reference/shift_c2st.md)

## Examples

``` r
shift_monitor()
#> <attest_check> Population stability shift <shift_monitor> [post]
# skip the null calibration on a latency-sensitive prediction path
shift_monitor(n_boot = 0)
#> <attest_check> Population stability shift <shift_monitor> [post]
```
