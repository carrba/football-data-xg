# ---------------------------------------------------------------------------
# IAM role for Lambda
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${var.project}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_models" {
  name = "${var.project}-lambda-s3-models"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.app.arn}/models/*"
    }]
  })
}
# ---------------------------------------------------------------------------
# Resolve the ":latest" tag to its current digest so that a new `docker push`
# is visible to Terraform. Pointing the Lambda at ":latest" directly doesn't
# work for deploys: the tag is a mutable string, so `terraform apply` sees no
# diff after a push and never rolls the function — you'd have to run
# `aws lambda update-function-code` by hand. Pinning to the digest here means
# a push changes the resolved digest, which *is* a plan diff, so `apply`
# rolls the function on its own the next time you run it.
# ---------------------------------------------------------------------------
data "aws_ecr_image" "xg_predict_latest" {
  repository_name = aws_ecr_repository.xg_predict.name
  image_tag       = "latest"
}

# ---------------------------------------------------------------------------
# Lambda function (container image from ECR)
# Build and push the image first — see outputs for the push commands.
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "xg_predict" {
  function_name = "${var.project}-predict"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.xg_predict.repository_url}@${data.aws_ecr_image.xg_predict_latest.image_digest}"
  timeout       = 120
  memory_size   = 1024

  environment {
    variables = {
      MODELS_BUCKET = aws_s3_bucket.app.id
      ORIGIN_SECRET = var.origin_secret
    }
  }
}

