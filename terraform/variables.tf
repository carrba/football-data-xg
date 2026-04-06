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

variable "origin_secret" {
  description = "Shared secret injected by CloudFront as X-Origin-Secret and validated by Lambda"
  type        = string
  sensitive   = true
}

variable "alarm_email" {
  description = "Email address to notify when an alarm fires (leave empty to skip)"
  type        = string
  default     = ""
}

variable "alarm_sms" {
  description = "Phone number (E.164 format, e.g. +447700900000) to notify when an alarm fires (leave empty to skip)"
  type        = string
  default     = ""
}
