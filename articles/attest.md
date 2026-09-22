# The attest contract: what a certificate guarantees, and what it does not

## The gap

A fitted model in R is an object that will answer any question you put
to it. Hand [`predict()`](https://rdrr.io/r/stats/predict.html) a row
from a population the model has never seen, a row with a feature ten
standard deviations outside the training range, or a row that has
drifted for six months since the model was fitted, and you get a number
back. The number carries no indication that it should not be trusted.

The validation you did lives somewhere else: in a script, a notebook, a
slide, a memory. Nothing binds it to the object. The object cannot tell
you whether it was ever checked for leakage, whether its probabilities
were calibrated, or on what data the claim was made. By the time the
model is in production, the evidence and the artefact have parted
company.

**attest** closes that gap by making the evidence part of the object and
the refusal part of the prediction path.

``` r

library(attest)
```

## The contract

An `attested_model` upholds four clauses.

1.  **Checks run at fit time, not on request.** Leakage, calibration,
    coverage and shift checks are executed by
    [`attest_fit()`](https://diogoribeiro7.github.io/attest/reference/attest_fit.md)
    itself. There is no code path that fits a model without running
    them.

2.  **Results are stored inside the object and bound by hash.** The
    certificate records every check, its statistic, its threshold, and
    SHA-256 hashes of the training features, the specification and the
    fitted model.

3.  **Predictions carry a validity status.** Every row comes back with
    an interval or label set, a `.status`, and a `.reason` when that
    status is not `valid`.

4.  **Refusal is the default.** Rows outside the certified support get
    `NA`, not a number. Overriding that requires `enforce = FALSE`, and
    the override is recorded on the returned object.

The unit of configuration is the *specification*:

``` r

spec <- attest_spec(split = split_random(prop = 0.2, calib = 0.2))
spec
#> 
#> ── attest_spec
#> split: split_random; on_fail: "refuse"
#> • Duplicate row leakage leak_duplicates (pre, blocking)
#> • Target proxy leakage leak_target_proxy (pre, blocking)
#> • Class imbalance imbalance_report (pre)
#> • Calibration error calib_ece (post, blocking)
#> • Conformal coverage conformal_split (post, blocking)
#> • Population stability shift shift_monitor (post)
```

[`default_checks()`](https://diogoribeiro7.github.io/attest/reference/attest_spec.md)
supplies the standard set. `on_fail` decides what a blocking failure
means: `"refuse"` (the default: no certificate,
[`attest_fit()`](https://diogoribeiro7.github.io/attest/reference/attest_fit.md)
errors), `"flag"` or `"warn"`.

## A certificate that issues

``` r

n <- 4000
d <- data.frame(x1 = rnorm(n), x2 = rnorm(n), x3 = runif(n, 0, 10))
d$y <- factor(rbinom(n, 1, plogis(0.8 * d$x1 - 0.5 * d$x2)))

m <- attest_fit(spec, y ~ x1 + x2 + x3, d, engine_glm())
#> ✔ Duplicate row leakage        pass        0.00% of test rows duplicate a training row (0 of 800)
#> ✔ Target proxy leakage         pass        max single-feature score 0.689 [0.668, 0.709]
#> i Class imbalance              info        minority/majority ratio 0.944 (0=1317, 1=1243)
#> ✔ Calibration error            pass        ECE = 0.036 [0.029, 0.075] (max 0.100)
#> ✔ Conformal coverage           pass        empirical coverage 0.894 [0.874, 0.917] (target 0.900)
#> i Population stability shift   info        baseline stored
#> ℹ Certificate 530ca4af7635 issued 2026-09-22 21:59:33 UTC (valid)
```

The checks report as they run, and a certificate is issued. It is worth
noticing that `x3` is pure noise: attest makes no claim that the model
is *good*, only that the stated checks were run and passed.

``` r

certificate(m)
#> 
#> ── Certificate 530ca4af7635 ──
#> 
#> issued 2026-09-22 21:59:33 UTC | status valid | on_fail "refuse"
#> task classification | engine glm | split split_random | n = 2560/640/800
#> (train/calib/test)
#> ✔ Duplicate row leakage        pass        0.00% of test rows duplicate a training row (0 of 800)
#> ✔ Target proxy leakage         pass        max single-feature score 0.689 [0.668, 0.709]
#> i Class imbalance              info        minority/majority ratio 0.944 (0=1317, 1=1243)
#> ✔ Calibration error            pass        ECE = 0.036 [0.029, 0.075] (max 0.100)
#> ✔ Conformal coverage           pass        empirical coverage 0.894 [0.874, 0.917] (target 0.900)
#> i Population stability shift   info        baseline stored
```

## A certificate that is refused

Now the case the package exists for. We add `score`, a feature that is
almost a restatement of the outcome – the classic shape of a leak, where
a field recorded downstream of the label finds its way into the training
frame.

``` r

leaky <- d
leaky$score <- ifelse(leaky$y == "1", rnorm(n, 3), rnorm(n, -3))
```

``` r

attest_fit(spec, y ~ x1 + x2 + x3 + score, leaky, engine_glm(), quiet = TRUE)
#> Warning: glm.fit: algorithm did not converge
#> Warning: glm.fit: fitted probabilities numerically 0 or 1 occurred
#> Error in `attest_fit()`:
#> ! refused to issue certificate (on_fail = "refuse")
#> ℹ blocking checks failed: leak_target_proxy
#> ℹ to proceed anyway: attest_fit(..., waive = <check id>, reason = "...")
```

No object is returned. The fit does not complete.

This is the point of the package, so it is worth being precise about
what just happened. Fit that same leaky model without the blocking check
and inspect it the way a careful analyst would:

``` r

peek <- attest_fit(
  attest_spec(on_fail = "flag"), y ~ x1 + x2 + x3 + score, leaky,
  engine_glm(),
  quiet = TRUE
)
compare <- function(x) {
  r <- certificate(x)$results
  c(
    ECE = r$calib_ece$statistic,
    coverage = r$conformal_split$statistic,
    q = r$conformal_split$evidence$q
  )
}
round(rbind(honest = compare(m), leaky = compare(peek)), 4)
#>           ECE coverage      q
#> honest 0.0361   0.8938 0.6807
#> leaky  0.0012   0.9988 0.0000
```

Read that table carefully, because it is the argument for the whole
package.

The leaky model is **better calibrated** by a factor of about thirty,
and its conformal quantile `q` collapses to zero – meaning its label
sets are singletons where the honest model mostly returns the
uninformative `{0,1}`. On the two properties a reviewer actually looks
at, calibration and sharpness, the leaking model is strictly better.
Leakage does not look like a problem in the metrics; it looks like
success.

Coverage, meanwhile, is near 0.89 for both, and that is neither a
coincidence nor a defect. Split conformal attains its target coverage
*by construction*, for any underlying model, however good or bad it is.
Coverage is a validity property of the procedure, not a quality signal
about the model. It cannot tell a leaking model from an honest one, and
it was never able to.

So neither calibration nor coverage will save you here: one is fooled,
the other is blind. That is why the leakage check has to run
automatically, at fit time, and block – rather than being one more
diagnostic a busy analyst is invited to consult.

Note also that `on_fail = "flag"` issues the certificate but marks it
`failed`, and a model whose certificate is not `valid` is not sealed, so
[`predict()`](https://rdrr.io/r/stats/predict.html) will refuse it.
Flagging lets you *inspect* a failing model; it does not let you use
one.

### Waivers are loud

Sometimes a check is wrong about your data. You can waive it, but not
silently: a waiver requires a reason, and that reason is written into
the certificate and reprinted in every report thereafter.

``` r

waived <- attest_fit(
  spec, y ~ x1 + x2 + x3 + score, leaky, engine_glm(),
  waive = "leak_target_proxy",
  reason = "score is a validated underwriting rating available before the claim",
  quiet = TRUE
)
#> Warning: glm.fit: algorithm did not converge
#> Warning: glm.fit: fitted probabilities numerically 0 or 1 occurred
certificate(waived)$waivers
#> $ids
#> [1] "leak_target_proxy"
#> 
#> $reason
#> [1] "score is a validated underwriting rating available before the claim"
```

The design intent is that a waiver is an on-the-record engineering
decision rather than a way to make a warning disappear.

## Predictions carry status

``` r

predict(m, d[1:5, ])
#> # attested_prediction: 5 rows, certificate 530ca4af7635
#> valid: 5 | flagged: 0 | refused: 0
#> # A tibble: 5 × 5
#>   .pred .set  .status .shift .reason
#> * <dbl> <chr> <chr>    <dbl> <chr>  
#> 1 0.760 {1}   valid   0.439  NA     
#> 2 0.503 {0,1} valid   0.415  NA     
#> 3 0.612 {0,1} valid   0.0567 NA     
#> 4 0.562 {0,1} valid   0.115  NA     
#> 5 0.816 {1}   valid   0.904  NA
```

`.set` is the conformal label set. A `{0,1}` row is not a failure – it
is the model declining to distinguish the classes at the requested
confidence level. An empty set [`{}`](https://rdrr.io/r/base/Paren.html)
is also possible, and means no label is plausible at that level: a
strong signal that the row does not belong.

Now feed it rows outside the training support:

``` r

nd <- d[1:5, ]
nd$x1 <- c(0.2, 12, -11, 0.5, 0)
predict(m, nd)
#> # attested_prediction: 5 rows, certificate 530ca4af7635
#> valid: 3 | flagged: 0 | refused: 2
#> # A tibble: 5 × 5
#>    .pred .set  .status  .shift .reason                     
#> *  <dbl> <chr> <chr>     <dbl> <chr>                       
#> 1  0.553 {0,1} valid   0.00655 NA                          
#> 2 NA     NA    refused 1       outside training support: x1
#> 3 NA     NA    refused 1       outside training support: x1
#> 4  0.535 {0,1} valid   0.0783  NA                          
#> 5  0.763 {1}   valid   0.893   NA
```

Rows 2 and 3 are refused. To see why that matters, override the
contract:

``` r

predict(m, nd, enforce = FALSE)
#> # attested_prediction: 5 rows, certificate 530ca4af7635 (NOT enforced)
#> valid: 3 | flagged: 0 | refused: 2
#> # A tibble: 5 × 5
#>      .pred .set  .status  .shift .reason                     
#> *    <dbl> <chr> <chr>     <dbl> <chr>                       
#> 1 0.553    {0,1} valid   0.00655 NA                          
#> 2 1.000    {1}   refused 1       outside training support: x1
#> 3 0.000173 {0}   refused 1       outside training support: x1
#> 4 0.535    {0,1} valid   0.0783  NA                          
#> 5 0.763    {1}   valid   0.893   NA
```

The refused rows come back maximally confident – probabilities pinned
near 1 and near 0 – on inputs the model has no evidence about.
Extrapolation does not announce itself as uncertainty; it announces
itself as certainty. Note that the object records `(NOT enforced)`, so
the override travels with the result.

### Shift is a batch property

Support is checked per row. Distribution shift is a property of a batch,
so it needs enough rows to estimate (`min_batch`, default 50):

``` r

big <- d[1:200, ]
big$x1 <- big$x1 + 2
pb <- predict(m, big)
table(pb$.status)
#> 
#> flagged refused 
#>     197       3
unique(pb$.reason[pb$.status == "flagged"])
#> [1] "PSI 3.82 > 0.20 on x1"
```

Most rows are individually inside the training range, so they are not
refused – but the *batch* has moved, and PSI catches it. Flagged means
the prediction is returned and the caller is told the population has
changed.

### What a per-feature statistic cannot see

PSI compares one feature at a time against its training bins. That makes
it cheap and interpretable – it names the feature that moved – but it is
blind by construction to a change in the *relationship* between
features. Consider two features whose marginal distributions are
untouched and whose correlation reverses:

``` r

correlated <- function(n, rho) {
  x <- rnorm(n)
  z <- rho * x + sqrt(1 - rho^2) * rnorm(n)
  data.frame(x = x, z = z, y = x + z + rnorm(n))
}
ref <- correlated(3000, 0.8)
flipped <- correlated(800, -0.8)
c(ref_sd_x = sd(ref$x), new_sd_x = sd(flipped$x))
#>  ref_sd_x  new_sd_x 
#> 0.9933461 1.0173461
```

Every marginal is where it was, so PSI has nothing to report. A
classifier asked to tell the two samples apart has no such difficulty:

``` r

r <- attest_c2st(ref, flipped, c("x", "z"))
c(auc = round(r$auc, 3), p_value = r$p_value)
#>           auc       p_value 
#>  9.040000e-01 1.153119e-270
```

[`shift_c2st()`](https://diogoribeiro7.github.io/attest/reference/shift_c2st.md)
adds that test to a specification. It stores a reference sample in the
certificate and runs the comparison at prediction time:

``` r

spec_c2st <- attest_spec(checks = c(default_checks(), list(shift_c2st())))
mc <- attest_fit(spec_c2st, y ~ x + z, ref, engine_glm(), quiet = TRUE)
unique(predict(mc, flipped)$.reason)
#> [1] "C2ST auc 0.90 (p 1.08e-242)"
```

The AUC is computed on held-out scores, by fitting on half the pooled
rows and scoring the other half. That is not fussiness: an in-sample AUC
is optimistic, because a flexible model can separate two *identical*
samples once it is allowed to fit and score the same rows, and it would
report shift where there is none. As with PSI, a flag needs both
statistical significance and an effect size — `auc_min` — because a
large enough batch makes any difference significant.

The two checks are complements. PSI is cheap, stores no data and names
the feature that moved; the classifier test costs a reference sample and
a model fit but sees structure PSI cannot.

## Checks know how uncertain they are

Every check statistic above is estimated from a finite sample, so
comparing a point estimate to a threshold decides borderline cases by
luck. Checks therefore report a bootstrap confidence interval, and the
verdict follows a three-way rule:

- **fail** – the whole interval clears the threshold. The violation is
  confident.
- **pass** – the whole interval is on the acceptable side.
- **weak** – the interval straddles the threshold. The evidence does not
  settle it.

``` r

attest_verdict(0.20, c(0.15, 0.25), threshold = 0.10, direction = "at_most")
#> [1] "fail"
attest_verdict(0.04, c(0.02, 0.06), threshold = 0.10, direction = "at_most")
#> [1] "pass"
attest_verdict(0.09, c(0.04, 0.15), threshold = 0.10, direction = "at_most")
#> [1] "weak"
```

A `weak` check passes by default, on the principle that noise alone
should not fail a model. But it is reported, stored in the certificate
and printed in the model card, so “we could not tell” is never silently
recorded as “fine”:

``` r

mid <- mean(certificate(m)$results$calib_ece$ci)
borderline <- attest_spec(checks = list(calib_ece(max = mid), shift_monitor()))
mw <- attest_fit(borderline, y ~ x1 + x2 + x3, d, engine_glm())
#> ? Calibration error            weak        ECE = 0.045 [0.033, 0.085] (max 0.052)
#> i Population stability shift   info        baseline stored
#> ! inconclusive: calib_ece -- interval straddles the threshold; treated as a pass (see `strict`)
#> Warning: no conformal check in the specification: predictions will have no
#> interval and will be refused
#> ℹ Certificate a992b1d0f204 issued 2026-09-22 21:59:38 UTC (valid)
```

This cuts against fail-closed defaults in one specific way, worth
stating plainly: intervals widen as data gets scarcer, so the smaller
your dataset, the harder it is for any check to fail. A package that
refuses by default would become most permissive exactly when evidence is
thinnest. `strict = TRUE` inverts that, treating an inconclusive check
as a failure:

``` r

attest_fit(
  attest_spec(checks = list(calib_ece(max = mid), shift_monitor()), strict = TRUE),
  y ~ x1 + x2 + x3, d, engine_glm(),
  quiet = TRUE
)
#> Error in `attest_fit()`:
#> ! refused to issue certificate (on_fail = "refuse")
#> ℹ blocking checks failed: calib_ece
#> ℹ to proceed anyway: attest_fit(..., waive = <check id>, reason = "...")
```

Not every check gets an interval.
[`leak_duplicates()`](https://diogoribeiro7.github.io/attest/reference/leak_duplicates.md)
reports none, because duplication is a census of the rows you hold
rather than an estimate of a population quantity: if a training row is
in your test set, it is there, and resampling would only describe some
other dataset.

PSI is a third case again. Its noise floor depends on the batch size, so
resampling the batch would not help – the bootstrap would inherit the
same small-sample bias. With ten bins, a batch of 50 rows drawn from the
*training distribution itself* has a median PSI of about 0.2, which is
the conventional flag threshold: the default settings would flag roughly
half of all healthy small batches. So the null is simulated instead,
drawing batches of the observed size from the stored training
frequencies, and a feature is flagged only when it beats both that null
and the effect-size threshold.

## Widening the interval instead of only warning

Flagging a drifted batch tells the caller something is wrong but still
hands back an interval calibrated on data that no longer resembles the
input. When the covariate distribution has moved but the relationship
between covariates and outcome has not, that is repairable: reweight the
calibration scores by the density ratio between the calibration set and
the incoming batch (Tibshirani et al., 2019).

Turn it on with `conformal_split(weighted = TRUE)`, which stores the
calibration scores and covariates in the certificate so
[`predict()`](https://rdrr.io/r/stats/predict.html) can reweight them:

``` r

gen <- function(n, mu = 0) {
  x1 <- rnorm(n, mu)
  x2 <- rnorm(n)
  data.frame(x1 = x1, x2 = x2, y = 2 * x1 - x2 + rnorm(n, sd = 0.4 + abs(x1)))
}
train <- gen(4000)

weighted <- attest_spec(checks = list(
  conformal_split(weighted = TRUE), shift_monitor()
))
plain <- attest_spec(checks = list(conformal_split(), shift_monitor()))
mw <- attest_fit(weighted, y ~ x1 + x2, train, engine_glm(), quiet = TRUE)
mp <- attest_fit(plain, y ~ x1 + x2, train, engine_glm(), quiet = TRUE)
```

The residual spread here grows with `x1`, so a batch drawn from larger
`x1` is genuinely harder to predict and a fixed calibration quantile is
too narrow:

``` r

coverage <- function(m, nd) {
  p <- predict(m, nd, enforce = FALSE)
  ok <- is.finite(p$.lower) & is.finite(p$.upper)
  c(
    coverage = mean(nd$y[ok] >= p$.lower[ok] & nd$y[ok] <= p$.upper[ok]),
    width = mean(p$.upper[ok] - p$.lower[ok])
  )
}
shifted <- gen(1500, mu = 1.5)
round(rbind(plain = coverage(mp, shifted), weighted = coverage(mw, shifted)), 3)
#>          coverage width
#> plain       0.761 4.599
#> weighted    0.897 6.822
```

The fixed quantile falls well short of its 0.90 target on shifted input
while reporting the same width it always reports. The reweighted
intervals widen and recover coverage. On an unshifted batch the two
agree, because every weight is near 1 and the weighted quantile reduces
exactly to the ordinary one:

``` r

round(rbind(
  plain = coverage(mp, gen(1500)),
  weighted = coverage(mw, gen(1500))
), 3)
#>          coverage width
#> plain       0.909 4.599
#> weighted    0.896 4.452
```

The estimated density ratio is returned per row, so you can see which
inputs the model considers unusual. Like PSI, it is a property estimated
*from the batch*: hand
[`predict()`](https://rdrr.io/r/stats/predict.html) a handful of rows
and there is nothing to compare the calibration set against, so every
weight falls back to 1 and the interval reverts to the fixed quantile.

``` r

p <- predict(mw, shifted)
p[1:5, c(".pred", ".lower", ".upper", ".weight")]
#> # A tibble: 5 × 4
#>    .pred  .lower .upper .weight
#>    <dbl>   <dbl>  <dbl>   <dbl>
#> 1  2.19  -1.17     5.54   4.73 
#> 2  3.42   0.0673   6.78   3.13 
#> 3 -0.793 -4.15     2.56   0.325
#> 4  0.888 -2.47     4.24   1.55 
#> 5  4.80   1.44     8.17   6.14
```

Weights rise with `x1`, which is exactly where this batch has moved and
where the residuals are widest:

``` r

tapply(p$.weight, cut(shifted$x1, c(-Inf, 0, 1, 2, 3, Inf)), mean)
#>   (-Inf,0]      (0,1]      (1,2]      (2,3]   (3, Inf] 
#>  0.5005283  1.8971952  6.7076406 24.6430869 76.4318978
```

`.status` keeps its meaning: `"flagged"` still says the batch moved, not
that the interval changed. What reweighting adds is that the interval
has already responded. A row whose weight is large relative to the whole
calibration set gets an infinite quantile – no finite interval is
justified – and is refused rather than returned as unbounded.

## The model card

[`report()`](https://diogoribeiro7.github.io/attest/reference/report.md)
renders Markdown entirely from the certificate, so it cannot drift from
the model it describes:

``` r

cat(report(m)[1:12], sep = "\n")
#> # Model card: y (classification)
#> 
#> Certificate `530ca4af7635`, issued 2026-09-22 21:59:33 UTC, status **valid** (on_fail = `refuse`), attest 0.1.0.
#> 
#> - Engine: `glm`
#> - Split: `split_random` -- train 2560 / calib 640 / test 800
#> - Features (3): `x1`, `x2`, `x3`
#> - Hashes: data `ccb2338c8b6d`, model `06e3c2482f3b`
#> 
#> ## Checks
#> 
#> | label | check | status | statistic | 95% CI | threshold | detail |
```

### A card you can send someone

`format = "html"` renders the same certificate as a self-contained page
with diagnostics drawn in. There are no external assets: the charts are
inline SVG, so the file can be mailed, committed or attached to a ticket
on its own.

``` r

card <- report(m, format = "html")
c(lines = length(card), charts = sum(grepl("<svg", card)))
#>  lines charts 
#>     76      2
```

``` r

f <- file.path(tempdir(), "model-card.html")
report(m, f, format = "html")
file.size(f)
#> [1] 7895
```

The page carries a reliability diagram and the empirical coverage curve
across alpha, so the single number each check reports can be read in
context: an ECE of 0.03 says little on its own, while the diagram shows
*where* the model is over- or under-confident.

Both are drawn from figures stored in the certificate at fit time, not
recomputed when the card is written. That is what keeps the rule from
the top of this vignette intact – the report cannot disagree with the
model, and that now extends to the pictures. Recomputing the ECE from
the stored bins returns the certificate’s own statistic, and the
coverage curve passes exactly through the certified point.

Passing `newdata` adds a shift section for that batch, with PSI per
feature against the bar it had to clear:

``` r

batch <- d[1:400, ]
batch$x1 <- batch$x1 + 1.5
shifted_card <- report(m, format = "html", newdata = batch)
any(grepl("Shift on the supplied batch", shifted_card))
#> [1] TRUE
```

Markdown remains the default and is unchanged, which is what you want
when the card is being embedded in a Quarto or R Markdown document
rather than read on its own.

## What a certificate does not guarantee

This section matters more than the rest of the vignette. A certificate
is evidence that stated checks were run and passed on stated data. It is
not a warranty, and reading it as one would be worse than having no
certificate at all.

**Conformal coverage is marginal, not conditional.** `alpha = 0.1` gives
intervals covering the truth about 90% of the time *averaged over the
population*. It says nothing about any particular row or subgroup.
Coverage can be 90% overall while being 99% for the bulk of your data
and 40% for a minority segment. If you need per-group validity, check it
per group; attest does not do this for you.

**Coverage is finite-sample and random.** Split conformal guarantees
`1 - alpha` coverage in expectation over draws of the calibration set,
within about `1 / (n_calib + 1)`. Empirical coverage on any one test set
scatters around the target, and a reading slightly below `1 - alpha` is
sampling noise rather than a broken guarantee. The `tolerance` argument
to
[`conformal_split()`](https://diogoribeiro7.github.io/attest/reference/conformal_split.md)
exists for exactly this reason.

**Coverage is not a measure of model quality.** As the leakage example
above shows, a conformal procedure hits its target coverage whatever
model it wraps. A useless model achieves 90% coverage by returning
enormous intervals or label sets containing every class. Coverage tells
you the procedure is valid; only sharpness – interval width, or the
quantile `q` – tells you it is useful. Read the two together or neither
means anything.

**Exchangeability is the whole assumption, and shift breaks it.** The
plain conformal guarantee holds when calibration and future data are
exchangeable. Under distribution shift it is simply void – not degraded
in a quantified way, void. This is the honest reason attest refuses
out-of-support rows: refusal is not an extra safety feature layered on
top of the guarantee, it is an admission that outside the training
support **there is no guarantee left to offer**. The refusal and the
interval are two halves of one claim.

**Reweighting buys back one kind of shift, not all of them.**
`conformal_split(weighted = TRUE)` restores an approximate guarantee
under *covariate* shift, where the covariate distribution moved but the
relationship between covariates and outcome did not. It does nothing for
label shift or concept drift – if the relationship itself changed,
reweighted intervals are not merely uncorrected but actively misleading,
because they look adjusted. And the guarantee assumes the density ratio
is known; attest estimates it from the batch, so coverage is
approximate. Under strong shift the weighted calibration set has a small
effective sample size, a handful of scores carry the quantile, and the
result is noisy and conservative – the table above shows over-coverage
setting in well before the method breaks. Treat a widened interval as a
better answer than one that ignores the shift, not as a restored
guarantee.

**Refusal is decided marginally, even though `.shift` is not.** A row is
refused when a feature falls outside its own training range, so a row
that sits inside every feature’s range but far from the joint
distribution – a 40-year-old with a 45-year career – is not refused. The
`.shift` score *does* see it, because it is a Mahalanobis position
within the joint training distribution rather than a count of tails, so
such a row scores near 1. But scoring it and refusing it are different
things: nothing in the refusal path consults `.shift`. Read it, and set
your own bar if joint implausibility should stop a prediction.

**PSI is a heuristic, and its threshold is an effect size.** The 0.2
line is convention, not theory. The batch size problem is handled – see
*Checks know how uncertain they are* above – and the dependence blind
spot is covered by
[`shift_c2st()`](https://diogoribeiro7.github.io/attest/reference/shift_c2st.md),
but PSI on its own still fires on harmless seasonal movement in a
feature the model barely uses. Because `threshold` acts as an
effect-size floor, a real but subtle shift is never flagged however many
rows you have. Treat a flag as a prompt to investigate, not a verdict.

**Detecting shift is not the same as knowing it matters.** Neither PSI
nor the classifier test looks at the outcome. They report that the input
distribution moved, which is not the same as the model having got worse:
a large shift in a feature the model ignores is harmless, while a subtle
shift in a decisive one may not be. Nothing here measures live accuracy,
because in production the labels have usually not arrived yet.

**The leakage checks are shallow by construction.**
[`leak_target_proxy()`](https://diogoribeiro7.github.io/attest/reference/leak_target_proxy.md)
fits one-variable models, so it finds single features that restate the
target. It will not find a leak spread across two features, nor one
mediated by a grouping structure.
[`leak_duplicates()`](https://diogoribeiro7.github.io/attest/reference/leak_duplicates.md)
finds exact duplicate rows, not near-duplicates. Passing means the
obvious leaks are absent, not that the data is clean.

**Duplication is not always leakage.**
[`leak_duplicates()`](https://diogoribeiro7.github.io/attest/reference/leak_duplicates.md)
tolerates nothing by default, which is right when a duplicate row means
the same record reached both partitions. On real data with
low-cardinality features some duplication is arithmetic instead: two
distinct subjects can share every recorded value. A motor portfolio of
68,000 policies described by seven mixed rating factors produces about
0.9% duplication with no leak present. The check reports the count as
well as the proportion so that `max_prop` can be set from the data
rather than guessed.

**Calibration is measured where it was measured.** ECE is computed on
the test split at fit time, with equal-width bins. It is a statement
about that data on that day. Nothing recomputes it later.

**Hashes prove integrity, not quality.**
[`verify()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
confirms the model object has not been altered since certification. It
does not, and cannot, confirm the training data was appropriate,
correctly labelled, or ethically obtained. `verify(x, data)` currently
checks only that the expected feature columns are present, because the
split cannot be reconstructed without the original seed.

**A certificate has a shelf life.** It is a claim about a moment.
Nothing in the object expires it, and a nine-month-old certificate on a
drifted population is a statement about a world that no longer exists.

The scope of the claim is deliberately narrow: *these checks, this data,
this moment*. Its value comes from being immutable, machine-readable and
attached to the artefact – not from being broad.

## More than two classes

A factor with more than two levels is a multiclass task, and the
conformal machinery generalises without a second mechanism: the
nonconformity score is still one minus the probability given to the true
class, and the prediction set is still every label whose score falls
within the quantile. With two classes that yields `{0}`, `{1}`, `{0,1}`
or [`{}`](https://rdrr.io/r/base/Paren.html); with more, it yields any
subset.

``` r

set.seed(21)
n <- 4000
mc <- data.frame(x1 = rnorm(n), x2 = rnorm(n))
lp <- cbind(0, 1.2 * mc$x1, 1.0 * mc$x2 - 0.5 * mc$x1)
pr <- exp(lp) / rowSums(exp(lp))
mc$y <- factor(apply(pr, 1, function(p) sample(c("a", "b", "c"), 1, prob = p)))

m_mc <- attest_fit(attest_spec(), y ~ x1 + x2, mc,
  engine_ranger(num.trees = 150),
  quiet = TRUE
)
predict(m_mc, mc[1:6, ])[, c(".pred", ".pred_class", ".set")]
#> # A tibble: 6 × 3
#>   .pred .pred_class .set   
#>   <dbl> <chr>       <chr>  
#> 1 0.484 b           {a,b,c}
#> 2 0.470 b           {b,c}  
#> 3 0.838 b           {b,c}  
#> 4 0.500 c           {a,b,c}
#> 5 0.816 b           {a,b}  
#> 6 0.669 c           {b,c}
```

`.pred_class` is the most probable label and `.pred` its probability, so
that column stays numeric whatever the task. The set is the honest part:
a row with `{a,b}` is the model saying it can rule out `c` at this
confidence level and no more. Set size is the multiclass equivalent of
interval width, and it is what tells you whether the model is useful –
coverage alone will not, for the reason set out earlier.

Everything else carries over: the same checks run,
[`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md)
reaches multiclass back ends, and `conformal_split(weighted = TRUE)`
reweights the same way. The exception is
[`engine_glm()`](https://diogoribeiro7.github.io/attest/reference/engines.md),
which fits binary outcomes only and says so rather than failing
obscurely inside [`glm()`](https://rdrr.io/r/stats/glm.html).

Two of the checks needed a multiclass definition rather than a
generalisation. Calibration uses top-label ECE: bin by the confidence
given to the predicted class, and compare it with how often that class
is right. Single-feature leakage cannot use a one-variable logistic fit,
so for multiclass the feature is binned and each bin predicts its
majority class, scored by mean per-class recall. A feature that
determines the outcome still scores one, which is what the check is
looking for.

## Keeping a record

A certificate travels inside the model object, which is enough while you
have the object. It does not tell you what a project has issued over
time, and it cannot tell you whether the model in front of you is the
one that was signed off. A ledger records every certificate a project
issues, as newline-delimited JSON:

``` r

led <- attest_ledger(file.path(tempdir(), "attest-ledger.ndjson"))
ledger_append(led, m, note = "nightly build")
ledger_append(led, mw, note = "reweighted regression")
led
#> <attest_ledger> /tmp/Rtmp0GmqrY/attest-ledger.ndjson -- 2 entries
```

Each entry carries the previous entry’s digest, so the file is a chain
rather than a pile.
[`verify()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
can then check a model in hand against the record:

``` r

verify(m, ledger = led)
#> [1] TRUE
#> attr(,"diff")
#> character(0)
```

Editing a record breaks its own digest; removing one breaks the link in
the record that followed it, because that entry still points at a digest
which is no longer there:

``` r

lines <- readLines(led$path)
writeLines(lines[-1], led$path) # delete the first entry
v <- ledger_verify(led)
c(intact = v, problem = attr(v, "problems")[1])
#>                             intact                            problem 
#>                            "FALSE" "entry 1: does not follow entry 0"
```

### What the seal proves, and what it does not

This is worth stating precisely, because the two modes differ in kind.

By default entries are sealed with a plain SHA-256 digest. That catches
accidental corruption, truncation and a single edited or deleted record
– as above. It does **not** withstand someone rewriting the whole chain,
which anyone with the package can do: they recompute every digest and
the file verifies again. A default ledger is a tamper-evident log
against accident and casual editing, not a signature.

Passing a secret key seals entries with an HMAC instead, and a rewritten
chain cannot be resealed without it:

``` r

signed <- attest_ledger(file.path(tempdir(), "signed.ndjson"), key = "keep-me-secret")
ledger_append(signed, m)
c(
  right_key = ledger_verify(signed),
  wrong_key = ledger_verify(attest_ledger(signed$path, key = "guess")),
  no_key = ledger_verify(attest_ledger(signed$path))
)
#> right_key wrong_key    no_key 
#>      TRUE     FALSE     FALSE
```

The guarantee then rests entirely on the key: anyone holding it can
rewrite the ledger undetectably, so it belongs outside the ledger,
outside the repository, and outside the script that writes it.

Two further limits. The ledger records that a certificate was *issued*,
not that the model behind it still exists or is unchanged – that is what
[`verify()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
on a model in hand is for. And appending reads the file and writes a
line, so two processes appending at once can corrupt it.

## Bringing your own model

attest ships adapters for `glm` and `ranger`, but the point is not to be
a modelling package.
[`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md)
accepts any parsnip specification, which reaches xgboost, glmnet, ranger
and the rest of that ecosystem without an adapter each:

``` r

library(parsnip)
m_gbm <- attest_fit(
  attest_spec(), y ~ x1 + x2 + x3, d,
  engine_parsnip(boost_tree(trees = 50)),
  quiet = TRUE
)
certificate(m_gbm)$engine
#> [1] "parsnip:boost_tree/xgboost"
```

The certificate records what was actually fitted rather than the word
`"parsnip"`, so a model card names the model and its back end. The
specification’s mode is taken from the outcome, so
[`set_mode()`](https://parsnip.tidymodels.org/reference/set_args.html)
is unnecessary; a mode that contradicts the outcome is an error rather
than a silent correction.

One requirement is not negotiable: the engine must produce probabilities
for classification. Without them there is nothing to calibrate and no
conformal label set to build, so an engine that cannot is rejected at
fit time rather than issuing a certificate whose checks mean nothing.

## Extending

Checks are the extension point. A check is a function of the fitting
context returning an
[`attest_result()`](https://diogoribeiro7.github.io/attest/reference/attest_result.md):

``` r

max_missing <- function(max_prop = 0.05) {
  new_check("max_missing", stage = "pre", blocking = TRUE, run = function(ctx) {
    prop <- mean(is.na(ctx$train[ctx$features]))
    attest_result(
      "max_missing",
      if (prop <= max_prop) "pass" else "fail",
      statistic = prop, threshold = max_prop,
      message = sprintf("%.1f%% of training feature cells missing", 100 * prop)
    )
  })
}

custom <- attest_spec(checks = c(default_checks(), list(max_missing())))
m2 <- attest_fit(custom, y ~ x1 + x2 + x3, d, engine_glm(), quiet = TRUE)
certificate(m2)$results$max_missing
#> $id
#> [1] "max_missing"
#> 
#> $label
#> [1] "Max missing"
#> 
#> $status
#> [1] "pass"
#> 
#> $statistic
#> [1] 0
#> 
#> $threshold
#> [1] 0.05
#> 
#> $ci
#> [1] NA NA
#> 
#> $message
#> [1] "0.0% of training feature cells missing"
#> 
#> $evidence
#> list()
#> 
#> attr(,"class")
#> [1] "attest_result"
```

`stage = "pre"` runs before fitting and sees only data; `stage = "post"`
runs after and sees `ctx$model`. Setting `blocking = FALSE` makes a
check informational – it is recorded in the certificate and appears in
the report, but never prevents issuance.
