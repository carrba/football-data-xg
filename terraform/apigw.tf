# Lambda Function URL — NONE auth; protected by X-Origin-Secret custom header
resource "aws_lambda_function_url" "xg_predict" {
  function_name      = aws_lambda_function.xg_predict.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["https://${aws_cloudfront_distribution.app.domain_name}"]
    allow_methods = ["POST"]
    allow_headers = ["Content-Type", "content-type"]
    max_age       = 300
  }
}

resource "aws_lambda_permission" "public_access" {
  statement_id           = "AllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.xg_predict.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
