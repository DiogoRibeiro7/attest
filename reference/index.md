# Package index

## Fitting and certifying

The entry point. A specification says what to check and what a failure
means; fitting runs the checks and issues the certificate.

- [`attest_spec()`](https://diogoribeiro7.github.io/attest/reference/attest_spec.md)
  [`default_checks()`](https://diogoribeiro7.github.io/attest/reference/attest_spec.md)
  : Build an attestation specification
- [`attest_fit()`](https://diogoribeiro7.github.io/attest/reference/attest_fit.md)
  : Fit a model and issue a certificate
- [`split_random()`](https://diogoribeiro7.github.io/attest/reference/splits.md)
  [`split_grouped()`](https://diogoribeiro7.github.io/attest/reference/splits.md)
  [`split_temporal()`](https://diogoribeiro7.github.io/attest/reference/splits.md)
  : Split strategies

## Inspecting a certificate

What the model attests, whether it is intact, and the model card
rendered from it.

- [`certificate()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
  [`is_sealed()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
  [`verify()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
  [`unseal()`](https://diogoribeiro7.github.io/attest/reference/certificate.md)
  : Inspect and verify certificates
- [`report()`](https://diogoribeiro7.github.io/attest/reference/report.md)
  : Render a model card from the certificate

## Predicting

Predictions carry a value, an interval or label set, a validity status
and a reason.

- [`predict(`*`<attested_model>`*`)`](https://diogoribeiro7.github.io/attest/reference/predict.attested_model.md)
  : Predict with validity status

## Leakage checks

- [`leak_duplicates()`](https://diogoribeiro7.github.io/attest/reference/leak_duplicates.md)
  : Leakage check: exact duplicate rows across train and test
- [`leak_target_proxy()`](https://diogoribeiro7.github.io/attest/reference/leak_target_proxy.md)
  : Leakage check: a single feature is a near-deterministic proxy of the
  target
- [`leak_temporal()`](https://diogoribeiro7.github.io/attest/reference/leak_temporal.md)
  : Leakage check: test rows must not precede training rows in time

## Calibration and coverage

Expected calibration error and split conformal coverage, the latter
optionally reweighted for covariate shift.

- [`calib_ece()`](https://diogoribeiro7.github.io/attest/reference/calib_ece.md)
  : Calibration check: expected calibration error on the test set
- [`conformal_split()`](https://diogoribeiro7.github.io/attest/reference/conformal_split.md)
  : Coverage check: split conformal prediction
- [`attest_weighted_quantile()`](https://diogoribeiro7.github.io/attest/reference/attest_weighted_quantile.md)
  : Weighted conformal quantile
- [`attest_density_ratio()`](https://diogoribeiro7.github.io/attest/reference/attest_density_ratio.md)
  : Estimate a covariate density ratio between calibration and new data

## Shift detection

A population stability monitor calibrated against a simulated null, and
a classifier two-sample test that sees changes in dependence structure a
per-feature statistic cannot.

- [`shift_monitor()`](https://diogoribeiro7.github.io/attest/reference/shift_monitor.md)
  : Shift monitor: population stability index baseline
- [`shift_c2st()`](https://diogoribeiro7.github.io/attest/reference/shift_c2st.md)
  : Shift check: classifier two-sample test on the prediction batch
- [`attest_c2st()`](https://diogoribeiro7.github.io/attest/reference/attest_c2st.md)
  : Classifier two-sample test

## Writing your own check

Checks are the extension point. The helpers are exported so a custom
check can use the same interval machinery as the built-in ones.

- [`new_check()`](https://diogoribeiro7.github.io/attest/reference/new_check.md)
  : Define a new check
- [`attest_result()`](https://diogoribeiro7.github.io/attest/reference/attest_result.md)
  : Create a check result
- [`attest_boot()`](https://diogoribeiro7.github.io/attest/reference/attest_boot.md)
  : Bootstrap a confidence interval for a check statistic
- [`attest_verdict()`](https://diogoribeiro7.github.io/attest/reference/attest_verdict.md)
  : Decide a check verdict from an interval and a threshold
- [`imbalance_report()`](https://diogoribeiro7.github.io/attest/reference/imbalance_report.md)
  : Class imbalance report (informational, never blocks)

## Engines

Thin adapters around modelling functions.
[`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md)
reaches the whole parsnip ecosystem without an adapter for each back
end.

- [`engine_glm()`](https://diogoribeiro7.github.io/attest/reference/engines.md)
  [`engine_ranger()`](https://diogoribeiro7.github.io/attest/reference/engines.md)
  : Engine adapters
- [`engine_parsnip()`](https://diogoribeiro7.github.io/attest/reference/engine_parsnip.md)
  : Fit any parsnip model under a certificate
- [`engine_fit()`](https://diogoribeiro7.github.io/attest/reference/engine_fit.md)
  : Fit a model with an engine
- [`engine_predict()`](https://diogoribeiro7.github.io/attest/reference/engine_predict.md)
  : Predict from an engine-fitted object

## Audit trail

An append-only, hash-chained record of every certificate a project
issues.

- [`attest_ledger()`](https://diogoribeiro7.github.io/attest/reference/attest_ledger.md)
  : An append-only ledger of issued certificates
- [`attest_manifest()`](https://diogoribeiro7.github.io/attest/reference/attest_manifest.md)
  : Build a portable manifest for an attested model
- [`ledger_append()`](https://diogoribeiro7.github.io/attest/reference/ledger_append.md)
  : Append a certificate to a ledger
- [`ledger_entries()`](https://diogoribeiro7.github.io/attest/reference/ledger_entries.md)
  : Read the entries of a ledger
- [`ledger_find()`](https://diogoribeiro7.github.io/attest/reference/ledger_find.md)
  : Find the ledger entry for a model
- [`ledger_verify()`](https://diogoribeiro7.github.io/attest/reference/ledger_verify.md)
  : Verify the integrity of a ledger chain
