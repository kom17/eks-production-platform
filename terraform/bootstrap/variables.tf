variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "github_repo" {
  description = "GitHub repo in owner/name form, e.g. johndoe/eks-production-platform"
  type        = string
}
