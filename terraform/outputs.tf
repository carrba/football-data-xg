output "website_url" {
  description = "S3 static website URL for the xG predictor page"
  value       = "http://${aws_s3_bucket_website_configuration.app.website_endpoint}"
}

output "lambda_function_url" {
  description = "Lambda function URL — use this as the endpoint in the web page"
  value       = aws_lambda_function_url.xg_predict.function_url
}

output "s3_bucket" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.app.id
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.xg_predict.repository_url
}

output "docker_push_commands" {
  description = "Commands to build and push the container image"
  value       = <<-EOT
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.xg_predict.repository_url}
    docker build --platform linux/amd64 -t ${aws_ecr_repository.xg_predict.repository_url}:latest ../src
    docker push ${aws_ecr_repository.xg_predict.repository_url}:latest
  EOT
}