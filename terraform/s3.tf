resource "aws_s3_bucket" "app" {
  bucket = "${var.project}-app"
}

# Block all public access — objects are served exclusively through CloudFront via OAC
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow CloudFront (identified by its distribution ARN via OAC) to read objects
resource "aws_s3_bucket_policy" "app_cloudfront" {
  bucket = aws_s3_bucket.app.id

  depends_on = [aws_s3_bucket_public_access_block.app]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.app.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = aws_cloudfront_distribution.app.arn
          }
        }
      }
    ]
  })
}

# Upload index.html
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.app.id
  key          = "index.html"
  source       = "${path.module}/../src/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../src/index.html")
}

# Upload pitch diagram
resource "aws_s3_object" "pitch_dims" {
  bucket       = aws_s3_bucket.app.id
  key          = "images/pitch_dims.jpg"
  source       = "${path.module}/../images/pitch_dims.jpg"
  content_type = "image/jpeg"
  etag         = filemd5("${path.module}/../images/pitch_dims.jpg")
}

# Upload ML models (private — accessed by Lambda via IAM)
resource "aws_s3_object" "model_xgboost" {
  bucket = aws_s3_bucket.app.id
  key    = "models/xgboost.pkl"
  source = "${path.module}/../models/xgboost.pkl"
  etag   = filemd5("${path.module}/../models/xgboost.pkl")
}

resource "aws_s3_object" "model_preprocessor" {
  bucket = aws_s3_bucket.app.id
  key    = "models/preprocessor.pkl"
  source = "${path.module}/../models/preprocessor.pkl"
  etag   = filemd5("${path.module}/../models/preprocessor.pkl")
}
