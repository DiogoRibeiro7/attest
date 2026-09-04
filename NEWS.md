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
  60-row batches falls from 78% to 5%, with detection of a genuine 0.5 SD
  shift unchanged at 88-100%. The per-feature quantile is Bonferroni-adjusted
  so the stated rate applies to the batch. Sampling from the baseline
  multinomial is independent of batch size, which also cuts the cost of
  predicting on 50,000 rows from 3.5 s to 0.25 s.
