#' attest: Fail-Closed Machine Learning with Model Certificates
#'
#' Fit predictive models that carry an immutable certificate of validity.
#' `attest` runs leakage, calibration, conformal coverage and distribution
#' shift checks at fit time, stores the results inside the model object, and
#' binds the certificate to the training data by hash. Predictions include an
#' interval and a validity status, and are refused by default when new inputs
#' fall outside the certified support. Reports are rendered from the
#' certificate so model cards stay tied to the fitted object.
#'
#' Start with [attest_spec()] to configure checks, [attest_fit()] to train and
#' certify a model, [predict.attested_model()] to make fail-closed predictions,
#' and [report()] to render a model card.
#'
#' @keywords internal
#' @importFrom stats predict
"_PACKAGE"
