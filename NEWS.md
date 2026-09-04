# attest 0.1.0

* Initial release: `attest_spec()`, `attest_fit()`, fail-closed `predict()`,
  `certificate()`, `verify()`, `report()`; engines `glm` and `ranger`;
  checks for duplicates, target proxies, temporal leakage, ECE, split
  conformal coverage and PSI shift.
* Vignette "The attest contract" states the guarantee and its limits: what a
  certificate covers, and what conformal coverage does not promise
  (marginal not conditional, void under shift, and not a quality signal).
