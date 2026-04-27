terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.42"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  profile = "itbc-test"
  region  = var.aws_region
}
