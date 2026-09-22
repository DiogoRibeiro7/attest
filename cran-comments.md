## Test environments

* local Windows 11, R 4.5.1
* GitHub Actions: ubuntu-latest (R devel, release, oldrel-1),
  macOS-latest (R release), windows-latest (R release)

## R CMD check results

0 errors | 0 warnings | 1 note

```
* checking CRAN incoming feasibility ... NOTE
Maintainer: 'Diogo Ribeiro <dfr@esmad.ipp.pt>'

New submission
```

The note is the expected one for a first submission; there is nothing else
to report.

## Notes for the reviewer

* All exported functions have `\value` and runnable `\examples`.
* Examples that fit models use small simulated data and run in well under
  five seconds each.
* `ranger`, `parsnip`, `glmnet`, `xgboost` and `xml2` are used only in
  examples and tests, each guarded by `requireNamespace()` or
  `skip_if_not_installed()`.
