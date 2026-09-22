# attest: Fail-Closed Machine Learning with Model Certificates

Fit predictive models that carry an immutable certificate of validity.
`attest` runs leakage, calibration, conformal coverage and distribution
shift checks at fit time, stores the results inside the model object,
and binds the certificate to the training data by hash. Predictions
include an interval and a validity status, and are refused by default
when new inputs fall outside the certified support. Reports are rendered
from the certificate so model cards stay tied to the fitted object.

## Details

Start with
[`attest_spec()`](https://diogoribeiro7.github.io/attest/reference/attest_spec.md)
to configure checks,
[`attest_fit()`](https://diogoribeiro7.github.io/attest/reference/attest_fit.md)
to train and certify a model,
[`predict.attested_model()`](https://diogoribeiro7.github.io/attest/reference/predict.attested_model.md)
to make fail-closed predictions, and
[`report()`](https://diogoribeiro7.github.io/attest/reference/report.md)
to render a model card.

## See also

Useful links:

- <https://github.com/DiogoRibeiro7/attest>

- <https://diogoribeiro7.github.io/attest/>

- Report bugs at <https://github.com/DiogoRibeiro7/attest/issues>

## Author

**Maintainer**: Diogo Ribeiro <dfr@esmad.ipp.pt>
([ORCID](https://orcid.org/0009-0001-2022-7072))
