terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95" # modules use a floor (>=); root stacks pin the exact range
    }
  }
}
