# Define a new check

Checks are the extension point of attest. A check is a function
`run(ctx)` receiving a context list with `train`, `test`, `calib`,
`model`, `task`, `outcome`, `features`, `spec` and returning an
[`attest_result()`](https://diogoribeiro7.github.io/attest/reference/attest_result.md).

## Usage

``` r
new_check(id, run, blocking = TRUE, stage = c("pre", "post"), label = NULL)
```

## Arguments

- id:

  Unique identifier.

- run:

  Function of one argument (the context list).

- blocking:

  If `TRUE` a `"fail"` blocks certification.

- stage:

  One of `"pre"` (before fitting; sees only data) or `"post"` (after
  fitting; sees the model).

- label:

  Human-readable label used in console output, certificates and reports.
  Defaults to a title-cased version of `id`.

## Value

An object of class `attest_check`.

## See also

Other checks:
[`attest_boot()`](https://diogoribeiro7.github.io/attest/reference/attest_boot.md),
[`attest_result()`](https://diogoribeiro7.github.io/attest/reference/attest_result.md),
[`attest_verdict()`](https://diogoribeiro7.github.io/attest/reference/attest_verdict.md),
[`imbalance_report()`](https://diogoribeiro7.github.io/attest/reference/imbalance_report.md)

## Examples

``` r
# a check that refuses training data with too many missing cells
max_missing <- new_check("max_missing", stage = "pre", run = function(ctx) {
  prop <- mean(is.na(ctx$train[ctx$features]))
  attest_result("max_missing", if (prop <= 0.05) "pass" else "fail",
    statistic = prop, threshold = 0.05
  )
})
max_missing
#> <attest_check> Max missing <max_missing> [pre, blocking]
```
