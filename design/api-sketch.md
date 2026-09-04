# attest — models that carry their own proof of validity

*API design sketch, v0 — Diogo Ribeiro, September 2026*

(Working name. Check `available::available("attest")` before committing; fallbacks: `warrant`, `vouch`, `certifyr`.)

## The contract

1. A model cannot be **reported or deployed** without a *certificate*: a set of checks run at fit time and stored inside the object.
2. A prediction is **never a bare number**. It is a prediction + interval + validity status.
3. The default on failure is **refuse**, not warn. Users can loosen it, but must do so explicitly and it is recorded in the certificate.
4. The certificate is **hash-bound** to the training data, the spec and the fitted weights. Tamper with any and the certificate is void.

Everything else is engineering around these four rules.

## Core objects

| Class | What it is |
|---|---|
| `attest_spec` | Declarative list of checks and thresholds (the "test plan") |
| `attest_check` | One check: `run(data, model) -> attest_result` |
| `attest_result` | `pass/fail/waived/untestable`, statistic, threshold, evidence |
| `certificate` | Immutable bundle of results + hashes + timestamps + waivers |
| `attested_model` | Fitted engine + `certificate` + conformal calibration set + shift baseline |
| `attested_prediction` | tibble: `.pred`, `.lower`, `.upper`, `.status`, `.shift`, `.reason` |

## Workflow

```r
library(attest)

spec <- attest_spec(
  split       = split_grouped(group = "patient_id", prop = 0.2),
  leakage     = list(
    leak_duplicates(),
    leak_target_proxy(threshold = 0.95),        # any feature ~ deterministic in y
    leak_temporal(time = "date")                # test rows precede train rows
  ),
  imbalance   = imbalance_report(),             # informational, never fails
  calibration = calib_ece(max = 0.05, bins = 15),
  coverage    = conformal_split(alpha = 0.10, score = "aps"),
  shift       = shift_monitor(method = "psi", threshold = 0.20),
  on_fail     = "refuse"                        # "refuse" | "flag" | "warn"
)

m <- attest_fit(
  spec,
  readmit ~ .,
  data   = ehr,
  engine = engine_ranger(num.trees = 500)
)
#> ✔ leak_duplicates      pass
#> ✔ leak_target_proxy    pass
#> ✔ leak_temporal        pass
#> ✔ calib_ece            pass   ECE = 0.031 (max 0.050)
#> ✔ conformal_split      pass   empirical coverage 0.903 (target 0.900)
#> ✔ shift_monitor        baseline stored
#> Certificate a3f9c… issued 2026-09-04 14:12:05 UTC

certificate(m)          # prints the ledger
is_sealed(m)            # TRUE

p <- predict(m, new_ehr)
p
#> # attested_prediction: 1,240 rows
#>   .pred .lower .upper .status  .shift .reason
#>   0.12  0.04   0.31   valid    0.03   NA
#>   0.44  0.20   0.71   flagged  0.27   "PSI > 0.20 on `age`, `los`"
#>   NA    NA     NA     refused  0.61   "feature `unit` outside support"
```

A failing check at fit time:

```r
m <- attest_fit(spec, y ~ ., data = d, engine = engine_glm())
#> ✖ leak_temporal   fail   38% of test rows precede last train row
#> Error: refused to issue certificate (on_fail = "refuse").
#>   To proceed anyway: attest_fit(..., waive = "leak_temporal", reason = "...")
```

Waivers are allowed but **must carry a reason string**, which is stored in the certificate and printed in every report. That is the social mechanism: you can lie, but you have to sign it.

## Verification and reporting

```r
verify(m, data = ehr)     # re-runs checks, compares hashes -> TRUE/FALSE + diff
report(m, file = "model_card.md")   # model card generated *from* the certificate
unseal(m)                 # returns the raw engine object; predictions lose status
```

`report()` is the CRAN-facing killer feature: it produces a model card that can't be out of sync with the model, because it is rendered from the object, not written by hand.

## Extension points

**Engines** — thin adapter, 3 methods:

```r
engine_fit(engine, formula, data)      -> fitted object
engine_predict(engine, object, newdata, type = c("prob", "numeric"))
engine_features(object)                -> character
```

Ship: `engine_glm`, `engine_ranger`, `engine_xgboost`, `engine_parsnip` (wraps any tidymodels spec), `engine_mlr3` (wraps any Learner). Engine packages go in `Suggests`, never `Imports`.

**Checks** — anyone can add one:

```r
check_new <- new_check(
  id   = "my_check",
  run  = function(train, test, model, ...) attest_result(...),
  fails = TRUE           # can this check block certification?
)
```

## What is new vs. what exists

| Piece | Exists in R? | attest's contribution |
|---|---|---|
| Resampling / splits | rsample, mlr3 | grouped/temporal split as a *checked* assumption |
| Leakage detection | scattered, mostly Python | first-class, blocking checks |
| Calibration | probably, CalibratR | threshold + block, not just a plot |
| Conformal prediction | probably, cfcausal | bound into every `predict()` |
| Drift monitoring | none mature on CRAN | baseline stored in model, evaluated per prediction |
| Model cards | none | generated from the certificate |
| Fail-closed prediction | none anywhere | the contract itself |

None of the individual checks is novel. The novelty is the **contract**: the object type makes the unsafe path the effortful one.

## Scope for v0.1 (CRAN-submittable)

- Binary classification and regression only.
- Engines: `glm`, `ranger`, `parsnip`.
- Checks: duplicates, target proxy, temporal, ECE, split conformal, PSI.
- `report()` to Markdown only.
- Pure R, `Imports` limited to `rlang`, `cli`, `tibble`, `digest`.

Leave for v0.2+: multiclass, survival (conformal survival is an open research area — potential paper), Bayesian engines, `S7` migration if it stabilises, HTML report.

## Risks to be honest about

- **Users will set `on_fail = "warn"` on day one.** Mitigation: the reason string is mandatory and printed; `report()` shows waivers in red. Accept that you cannot stop determined people.
- **Conformal coverage is marginal, not conditional.** The interval is honest on average, not per-row. The docs must say this loudly or the package over-promises exactly what it claims to prevent.
- **PSI is a crude shift detector.** Ship it because it is interpretable; add MMD / classifier two-sample test as options.
- **CRAN reviewers will ask why not a tidymodels extension.** Answer: the fail-closed prediction type cannot be implemented as a `parsnip` extension without breaking `predict()` semantics — that is the point.

## Companion outputs

- JOSS paper: "attest: fail-closed machine learning in R".
- Methods paper (arXiv, then a stats/ML journal): the certificate as a formal object — what it guarantees, what it cannot, and the conformal-under-shift question.
- Zenodo DOI per release.
