# Lambda Function URL — NONE auth; protected by X-Origin-Secret custom header.
# No CORS block here — browsers never hit this URL directly (all traffic goes via CloudFront).
resource "aws_lambda_function_url" "xg_predict" {
  function_name      = aws_lambda_function.xg_predict.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "public_access" {
  statement_id           = "AllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.xg_predict.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
