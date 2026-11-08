terraform {
  required_version = ">= 1.11"

  # The bucket is made by hand and shared by hobby projects, each under its
  # own prefix. Its name is supplied through the ignored backend.hcl file.
  backend "s3" {
    key          = "fusion/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = "eu-west-2"

  # Marks every resource as part of the project. Default tags do not reach
  # the root volume or the network interface; those are tagged explicitly.
  default_tags {
    tags = {
      Project = "fusion"
    }
  }
}
