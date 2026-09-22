# Create a check result

Every check returns one of these. `status` is one of `"pass"`, `"weak"`,
`"fail"`, `"waived"`, `"untestable"` or `"info"`.

## Usage

``` r
attest_result(
  id,
  status,
  statistic = NA_real_,
  threshold = NA_real_,
  ci = c(NA_real_, NA_real_),
  message = "",
  evidence = list(),
  label = NULL
)
```

## Arguments

- id:

  Check identifier.

- status:

  One of `"pass"`, `"weak"`, `"fail"`, `"waived"`, `"untestable"`,
  `"info"`.

- statistic:

  Numeric statistic (may be `NA`).

- threshold:

  Numeric threshold (may be `NA`).

- ci:

  Numeric vector of length 2, the lower and upper bounds of a confidence
  interval for `statistic`. `c(NA, NA)` when not estimated.

- message:

  Human-readable summary.

- evidence:

  Optional list of supporting objects.

- label:

  Human-readable check label. When omitted, a label is derived from
  `id`.

## Value

An object of class `attest_result`.

## Details

`"weak"` means the statistic's confidence interval straddles the
threshold: the check neither confidently passed nor confidently failed.
See
[`attest_verdict()`](https://diogoribeiro7.github.io/attest/reference/attest_verdict.md).

## See also

Other checks:
[`attest_boot()`](https://diogoribeiro7.github.io/attest/reference/attest_boot.md),
[`attest_verdict()`](https://diogoribeiro7.github.io/attest/reference/attest_verdict.md),
[`imbalance_report()`](https://diogoribeiro7.github.io/attest/reference/imbalance_report.md),
[`new_check()`](https://diogoribeiro7.github.io/attest/reference/new_check.md)

## Examples

``` r
attest_result("my_check", "weak",
  statistic = 0.04,
  threshold = 0.05, ci = c(0.02, 0.09)
)
#> $id
#> [1] "my_check"
#> 
#> $label
#> [1] "My check"
#> 
#> $status
#> [1] "weak"
#> 
#> $statistic
#> [1] 0.04
#> 
#> $threshold
#> [1] 0.05
#> 
#> $ci
#> [1] 0.02 0.09
#> 
#> $message
#> [1] ""
#> 
#> $evidence
#> list()
#> 
#> attr(,"class")
#> [1] "attest_result"
```
