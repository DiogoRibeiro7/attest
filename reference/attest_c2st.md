# Classifier two-sample test

Tests whether two samples come from the same distribution by asking how
well a classifier can tell them apart. An AUC near 0.5 means the samples
are indistinguishable; an AUC near 1 means a model can separate them,
which is what distribution shift looks like.

## Usage

``` r
attest_c2st(reference, new, features, interactions = TRUE, max_terms = 8)
```

## Arguments

- reference:

  Data frame of reference (training-time) rows.

- new:

  Data frame of incoming rows.

- features:

  Columns to compare.

- interactions:

  If `TRUE` and the feature count is small, the classifier gets squared
  terms and pairwise interactions. Without them a linear classifier only
  sees shifts in means, and is blind to a change in the dependence
  between features that leaves every marginal intact – exactly the case
  a per-feature statistic such as PSI also misses.

- max_terms:

  Maximum number of features for which `interactions` is honoured,
  keeping the fit affordable.

## Value

A list with `auc` (held-out), `p_value` (one-sided, against the null of
no shift), `n_ref` and `n_new`.

## Details

Scores are produced by cross-fitting: the pooled data is split in two,
each half is scored by a model fitted on the other, and the AUC is
computed on those held-out scores. This matters, because an in-sample
AUC is optimistic – a flexible model can separate two identical samples
if it is allowed to fit and score the same rows – and would report shift
where there is none.

Because the scores are held out, under the null the labels are
independent of them and the AUC is a Mann-Whitney statistic, so the
p-value uses that standard normal approximation rather than needing a
permutation loop.

## See also

Other shift checks:
[`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md),
[`shift_c2st()`](https://diogoribeiro7.github.io/attest/reference/shift_c2st.md),
[`shift_monitor()`](https://diogoribeiro7.github.io/attest/reference/shift_monitor.md)

## Examples

``` r
set.seed(1)
a <- data.frame(x = rnorm(300), z = rnorm(300))
same <- data.frame(x = rnorm(300), z = rnorm(300))
shifted <- data.frame(x = rnorm(300, 1), z = rnorm(300))
round(attest_c2st(a, same, c("x", "z"))$p_value, 3)
#> [1] 0.055
round(attest_c2st(a, shifted, c("x", "z"))$p_value, 3)
#> [1] 0
```
