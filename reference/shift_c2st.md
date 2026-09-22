# Shift check: classifier two-sample test on the prediction batch

Stores a reference sample of the training rows. At prediction time a
classifier is asked to tell that reference from the incoming batch,
using held-out scores; an AUC near 0.5 means the two are
indistinguishable. See
[`attest_c2st()`](https://diogoribeiro7.github.io/attest/reference/attest_c2st.md)
for the mechanics.

## Usage

``` r
shift_c2st(
  auc_min = 0.6,
  alpha = 0.05,
  max_ref = 2000,
  min_batch = 50,
  interactions = TRUE
)
```

## Arguments

- auc_min:

  Minimum held-out AUC before a batch is flagged, an effect size floor.

- alpha:

  Significance level for the test.

- max_ref:

  Maximum number of training rows stored as the reference sample. Larger
  gives more power and a larger certificate.

- min_batch:

  Minimum incoming rows before the test is attempted.

- interactions:

  Passed to
  [`attest_c2st()`](https://diogoribeiro7.github.io/attest/reference/attest_c2st.md);
  keep `TRUE` to detect changes in the dependence between features.

## Value

An `attest_check`.

## Details

This complements
[`shift_monitor()`](https://diogoribeiro7.github.io/attest/reference/shift_monitor.md)
rather than replacing it. PSI is computed per feature on binned
marginals, so it cannot see a change in the relationship *between*
features. Two samples with identical marginals but opposite correlation
produce no PSI signal at all, while the classifier separates them
easily. Conversely PSI is cheaper, needs no reference sample stored in
the certificate, and says which feature moved.

A batch is flagged only when the test is both significant at `alpha` and
the held-out AUC reaches `auc_min`. The second bar matters because a
large enough batch makes an arbitrarily small difference significant,
and a shift too small to separate the samples is rarely a shift worth
acting on.

## See also

Other shift checks:
[`attest_c2st()`](https://diogoribeiro7.github.io/attest/reference/attest_c2st.md),
[`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md),
[`shift_monitor()`](https://diogoribeiro7.github.io/attest/reference/shift_monitor.md)

## Examples

``` r
shift_c2st()
#> <attest_check> Classifier two-sample shift <shift_c2st> [post]
# demand a clearer separation before flagging
shift_c2st(auc_min = 0.7)
#> <attest_check> Classifier two-sample shift <shift_c2st> [post]
```
