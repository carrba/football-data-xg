# Origin Access Control — S3 REST API (sigv4 signing, OAC preferred over legacy OAI)
resource "aws_cloudfront_origin_access_control" "app" {
  name                              = "${var.project}-app-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project} static site"
  price_class         = "PriceClass_100" # US, Canada, Europe

  origin {
    domain_name              = aws_s3_bucket.app.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.app.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.app.id
  }

  origin {
    domain_name = trimprefix(trimsuffix(aws_lambda_function_url.xg_predict.function_url, "/"), "https://")
    origin_id   = "lambda-xg-predict"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Secret"
      value = var.origin_secret
    }
  }

  # POST /predict — routed to Lambda URL, not cached
  ordered_cache_behavior {
    path_pattern           = "/predict"
    target_origin_id       = "lambda-xg-predict"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      headers      = ["Content-Type"]
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.app.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["GB"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
