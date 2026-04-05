resource "aws_s3_bucket" "app" {
  bucket = "${var.project}-app"
}

# Block all public access to the bucket by default; we grant read via bucket policy
resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  index_document {
    suffix = "index.html"
  }
}

# Public read policy for the index.html static site only
resource "aws_s3_bucket_policy" "app_public_read" {
  bucket = aws_s3_bucket.app.id

  depends_on = [aws_s3_bucket_public_access_block.app]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadStatic"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = [
          "${aws_s3_bucket.app.arn}/index.html",
          "${aws_s3_bucket.app.arn}/images/*"
        ]
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
