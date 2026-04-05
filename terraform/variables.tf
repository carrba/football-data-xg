variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Project name prefix used for resource naming"
  type        = string
  default     = "football-xg"
}
