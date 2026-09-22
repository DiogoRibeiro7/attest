---
title: 'attest: fail-closed machine learning with model certificates in R'
tags:
  - R
  - machine learning
  - conformal prediction
  - data leakage
  - calibration
  - distribution shift
  - reproducibility
authors:
  - name: Diogo Ribeiro
    orcid: 0009-0001-2022-7072
    affiliation: 1
affiliations:
  - name: Faculty of Media Arts and Design, Technical University of Porto, Portugal
    index: 1
date: 22 September 2026
bibliography: paper.bib
---

# Summary

A fitted model in R will answer any question put to it. Hand `predict()` a row
from a population the model has never seen, or one that has drifted for six
months, and a number comes back carrying no indication that it should not be
trusted. The validation that justified the model lives elsewhere — in a script,
a notebook, a slide — and nothing binds it to the object. By the time a model
reaches production, the evidence and the artefact have parted company.

`attest` closes that gap by making the evidence part of the object and refusal
part of the prediction path. A model fitted with `attest_fit()` carries a
**certificate**: leakage, calibration, conformal coverage and
distribution-shift checks that run at fit time and are stored inside the model,
bound to the training data, the specification and the fitted object by SHA-256
hash. Predictions are not bare numbers. Each row returns an interval (regression)
or a conformal label set (classification), a validity status, and a reason when
that status is not `valid`. Rows falling outside the certified support are
refused rather than answered, and overriding that refusal is recorded on the
returned object. Model cards are rendered from the certificate, in Markdown or
as a self-contained HTML page with diagnostic charts, so a report cannot
disagree with the model it describes.

The package wraps existing modelling tools rather than replacing them.
`engine_parsnip()` accepts any `parsnip` [@parsnip] specification, which reaches
`ranger` [@ranger], `xgboost` and `glmnet` without an adapter for each, and the
certificate records which model was actually fitted.

# Statement of need

Tooling for trustworthy machine learning in R is plentiful but optional.
Calibration, leakage screening and conformal prediction are each available as
separate packages, and each must be remembered, invoked and interpreted by the
analyst. Nothing prevents a model from being deployed without them, and nothing
records afterwards whether they were run. The failure mode is not that the
checks are unavailable; it is that they are easy to skip and impossible to
audit after the fact.

`attest` inverts the default. Checks execute inside `attest_fit()`, so there is
no code path that fits a model without them. A blocking failure refuses to
issue a certificate at all, and a model whose certificate is not valid cannot
predict. Waiving a check is possible but requires a written reason, which is
stored in the certificate and reprinted in every report thereafter. The package
is aimed at regulated and safety-adjacent settings — credit, insurance pricing,
clinical triage — where the question asked of a model is not only how accurate
it is, but what was checked, on what data, and by whom.

Two design commitments distinguish it from a checklist.

**Every threshold is compared against a null.** Checks report a bootstrap
confidence interval alongside each statistic and fail only when the whole
interval clears the threshold, so sampling noise alone cannot fail a model; an
interval straddling the threshold is reported as `weak` rather than silently
passing. This matters in practice. The population stability index, the
conventional shift statistic, is biased upward in small batches: with ten bins
and 50 rows drawn from the training distribution itself, its median value is
approximately 0.2, the conventional flag threshold. Comparing against a
simulated null at the observed batch size rather than a fixed line reduces the
measured false-positive rate on unshifted 50-row batches, the package default
minimum, from roughly 80% to 6%, while leaving detection of a genuine shift
unchanged. A classifier two-sample test
[@lopezpaz2017] complements it, detecting changes in the dependence between
features that any per-feature statistic misses by construction.

**Refusal is where the guarantee ends, not an extra safeguard.** Split conformal
prediction [@vovk2005; @lei2018] provides marginal coverage under
exchangeability, and that assumption is void — not merely weakened — under
distribution shift. `attest` refuses rows outside the certified support because
outside it there is no guarantee left to offer. Where the covariate distribution
has moved but the conditional distribution of the outcome has not,
`conformal_split(weighted = TRUE)` reweights the calibration scores by an
estimated density ratio [@tibshirani2019], widening intervals instead of only
warning. On a heteroscedastic problem shifted by 1.5 standard deviations, a
fixed quantile covers approximately 0.74 against a 0.90 target while reporting
its usual width; the reweighted intervals cover 0.95. When every weight is one the
weighted quantile reduces exactly to the ordinary one, so enabling it costs
nothing when nothing has moved.

The documentation is explicit about what a certificate does not establish.
Conformal coverage is marginal rather than conditional; it is achieved by
construction for any underlying model and therefore cannot distinguish a
leaking model from an honest one; reweighting corrects covariate shift only and
is actively misleading under concept drift; and no shift check inspects the
outcome, so none of them can tell that the input distribution moved from that
the model became worse.

# Acknowledgements

`attest` builds on `cli`, `digest`, `jsonlite`, `rlang` and `tibble`.

# References
