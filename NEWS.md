# attest 0.1.0

* Initial release: `attest_spec()`, `attest_fit()`, fail-closed `predict()`,
  `certificate()`, `verify()`, `report()`; engines `glm` and `ranger`;
  checks for duplicates, target proxies, temporal leakage, ECE, split
  conformal coverage and PSI shift.
* Vignette "The attest contract" states the guarantee and its limits: what a
  certificate covers, and what conformal coverage does not promise
  (marginal not conditional, void under shift, and not a quality signal).
* Checks report a bootstrap confidence interval alongside the point estimate,
  and the certificate stores it. `attest_boot()` and `attest_verdict()` are
  exported so user-defined checks can use the same machinery.
* A check now fails only when its whole interval clears the threshold. When
  the interval straddles the threshold the status is the new `"weak"`, which
  passes by default but is recorded and reported. `attest_spec(strict = TRUE)`
  treats `"weak"` as a failure, for the case where scarce data must not earn a
  certificate by widening intervals.
* PSI shift flags are calibrated against a simulated null at the incoming
  batch size rather than a fixed 0.2 line. PSI is biased upward in small
  batches -- with ten bins, 50 rows drawn from the training distribution
  itself have a median PSI near 0.2 -- so the old default flagged roughly half
  of all healthy small batches. Measured false-positive rate on unshifted
  50-row batches, the default minimum, falls from roughly 80% to 6%, with
  detection of a genuine 0.5 SD shift unchanged at 88-100%. The per-feature quantile is Bonferroni-adjusted
  so the stated rate applies to the batch. Sampling from the baseline
  multinomial is independent of batch size, which also cuts the cost of
  predicting on 50,000 rows from 3.5 s to 0.25 s.
* `conformal_split(weighted = TRUE)` reweights the calibration scores at
  prediction time by an estimated covariate density ratio, following
  Tibshirani et al. (2019), so intervals widen on drifted batches instead of
  only being flagged. On a heteroscedastic problem shifted by 1.5 SD, a fixed
  quantile covers 0.74 against a 0.90 target while the reweighted intervals
  cover 0.95; on unshifted data the two agree, because the weighted quantile
  reduces exactly to the ordinary one when every weight is 1. `.status` keeps
  its meaning -- `"flagged"` still reports that the batch moved -- and the
  estimated ratio is returned in a new `.weight` column. Rows whose reweighted
  quantile is infinite are refused rather than given an unbounded interval.
  This corrects covariate shift only: it does nothing for label shift or
  concept drift, and with an estimated ratio the coverage is approximate.
* `attest_density_ratio()` and `attest_weighted_quantile()` are exported for
  use outside the package.
* `print()` on an `attested_prediction` no longer warns when the object has
  been subset to drop the `.status` column.
* `shift_c2st()` adds a classifier two-sample test: a model is asked to tell a
  stored reference sample from the incoming batch, and an AUC near 0.5 means
  they are indistinguishable. It sees what a per-feature statistic cannot. On
  two samples with identical marginals whose correlation reverses, PSI reports
  nothing at all while the test reaches AUC 0.90. Scores are cross-fitted,
  because an in-sample AUC reads 0.53 on two identical samples where the
  cross-fitted figure correctly reads 0.49. A batch is flagged only when the
  test is significant and the AUC clears `auc_min`, mirroring how the PSI
  monitor pairs its simulated null with a threshold.
* `attest_c2st()` is exported for use outside the package.
* `.shift` is now the row's Mahalanobis position within the joint training
  distribution on a chi-square probability scale, rather than the share of
  features in their tails. A row that is unremarkable on every feature alone
  but implausible in combination now scores near 1 where it previously scored
  low. It falls back to the old measure when a model has no numeric features.
* `engine_parsnip()` fits any parsnip model specification under a
  certificate, so xgboost, glmnet, ranger and the rest of that ecosystem work
  without an adapter each. The mode is taken from the outcome rather than
  needing `set_mode()`, and a mode contradicting the outcome is an error. The
  certificate records the specification as `parsnip:<model>/<engine>` rather
  than the bare word `parsnip`, so a model card says what was fitted.
* The specification hash is computed from a structural fingerprint instead of
  by serialising the checks. Serialising a closure is not a stable operation:
  the just-in-time compiler attaches bytecode to a function once it has run,
  so the same specification hashed before and after use gave different
  answers, and two identical fits produced different certificate ids.
  Identical fits now produce identical certificates, and the hash is sensitive
  to the thresholds a check was built with.
* `attest_ledger()` records every certificate a project issues to a
  newline-delimited JSON file, with `ledger_append()`, `ledger_entries()`,
  `ledger_find()` and `ledger_verify()`. Each entry carries the previous
  entry's digest, so the log is a chain: editing a record breaks its own
  digest and removing one breaks the link in the record that followed it.
  `attest_manifest()` returns the same facts as plain data for a single model.
* `verify()` gains a `ledger` argument, checking that a model was recorded,
  that its three hashes match the record, and that the chain is intact.
* Ledger entries are sealed with a plain SHA-256 digest by default, which
  catches accidents, truncation and single edits but not a rewritten chain --
  anyone with the package can recompute every digest. Passing a secret `key`
  seals entries with an HMAC instead, which a rewritten chain cannot reproduce.
  Both behaviours are covered by tests, including the forgery that succeeds
  without a key.
* jsonlite moves into Imports for the ledger format.
* Multiclass outcomes are supported. A factor with more than two levels is a
  `"multiclass"` task, and the conformal machinery generalises without a second
  mechanism: the score is still one minus the probability of the true class and
  the set is still every label within the quantile. Measured set coverage
  tracks the target across alpha (0.937, 0.890 and 0.793 against 0.95, 0.90 and
  0.80), with set size shrinking as alpha grows.
* Multiclass predictions gain `.pred_class`, the most probable label, while
  `.pred` becomes that label's probability so the column stays numeric across
  tasks.
* `engine_predict()` gains a `"prob_matrix"` type returning one column per
  class in level order, implemented for ranger and parsnip. `engine_glm()`
  fits binary outcomes only and now says so at fit time rather than failing
  inside `glm()`.
* Two checks needed a multiclass definition rather than a generalisation.
  `calib_ece()` uses top-label ECE. `leak_target_proxy()` cannot use a
  one-variable logistic fit, so it bins the feature and lets each bin predict
  its majority class; a feature that determines the outcome still scores near
  one.
* `report()` gains `format = "html"`, rendering the certificate as a
  self-contained page with a reliability diagram, the empirical coverage curve
  across alpha, and a check table. The charts are inline SVG written by hand,
  so the card has no external assets and the package gains no plotting
  dependency. Markdown remains the default and is unchanged.
* The charts are drawn from figures stored in the certificate at fit time
  rather than recomputed when the card is written, so a card cannot disagree
  with the model it describes. Tests assert that recomputing the ECE from the
  stored bins returns the certificate's own statistic, and that the coverage
  curve passes through the certified point.
* `report()` gains `newdata`, adding a shift section with PSI per feature for a
  supplied batch.
* Certificates now store per-bin calibration figures and a coverage curve.
* Checks and results carry a human-readable `label` alongside their `id`,
  shown in console output, `print()` on a specification, and both report
  formats, which now have a label column beside the identifier. Built-in
  checks have written labels; anything else is title-cased from its `id`, and
  `new_check(label =)` or `attest_result(label =)` override that. The `id`
  remains what you pass to `waive`, so the refusal message still quotes it.
* Help topics are grouped with `@family`, so related checks, engines and
  ledger functions cross-reference each other.
* `leak_target_proxy()` scores a feature by AUC for a binary outcome and by
  mean per-class recall for multiclass, rather than by accuracy. Accuracy
  tracks the base rate, because a majority-class rule already achieves it: on
  a rare outcome every feature, noise included, scored close to one. Found on
  real motor insurance data with a 6.8% claim rate, where all seven rating
  factors scored 0.9318 against a no-claim rate of 0.9319. At a 2.6% event
  rate the old statistic flagged pure noise and refused every model, which
  would have made the package unusable on the rare-event problems it is aimed
  at. The new statistics sit at chance for a useless feature however skewed
  the outcome, and at one for a feature that reproduces it. Regression keeps
  R-squared, which was never balance-sensitive.
* `leak_duplicates()` reports the number of duplicated rows as well as the
  proportion. The zero-tolerance default is unchanged, but the help and the
  vignette now record that real data with low-cardinality features produces
  some duplication arithmetically rather than through leakage -- about 0.9% in
  a 68,000-policy motor portfolio -- so `max_prop` can be set from the data.
