# Render a model card from the certificate

The report is generated entirely from the `attested_model` object, so it
cannot drift from the model.

## Usage

``` r
report(x, file = NULL, format = c("md", "html"), newdata = NULL)
```

## Arguments

- x:

  An `attested_model`.

- file:

  Optional path; if `NULL` the text is returned.

- format:

  `"md"` for Markdown, the default, or `"html"` for a self-contained
  page with diagnostic charts. The HTML has no external assets: the
  charts are inline SVG, so the file can be mailed or committed on its
  own.

- newdata:

  Optional batch. When supplied to the HTML format, the card gains a
  shift section for that batch. Everything else is drawn from the
  certificate alone, so it cannot disagree with the model.

## Value

Invisibly, the text (a character vector of lines).

## Examples

``` r
set.seed(1)
d <- data.frame(x1 = rnorm(1000), x2 = rnorm(1000))
d$y <- factor(rbinom(1000, 1, plogis(d$x1 - d$x2)))
m <- attest_fit(attest_spec(), y ~ x1 + x2, d, engine_glm(), quiet = TRUE)
cat(report(m)[1:8], sep = "\n")
#> # Model card: y (classification)
#> 
#> Certificate `b897d5d357d5`, issued 2026-09-22 21:59:29 UTC, status **valid** (on_fail = `refuse`), attest 0.1.0.
#> 
#> - Engine: `glm`
#> - Split: `split_random` -- train 640 / calib 160 / test 200
#> - Features (2): `x1`, `x2`
#> - Hashes: data `2146f198f0f7`, model `8efc81e42431`
```
