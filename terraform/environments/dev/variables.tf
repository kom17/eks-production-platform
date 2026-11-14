variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "kubernetes_version" {
  description = "EKS version. Check `aws eks describe-cluster-versions` for currently supported versions."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "admin_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public EKS API endpoint. Every request is still
    IAM-authenticated. GitHub-hosted runners have no fixed IPs, so CI needs
    0.0.0.0/0 here; in a real prod setup use self-hosted runners inside the VPC
    and turn public access off.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "github_repo" {
  description = "owner/name, used to scope the app CI OIDC role"
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "From the bootstrap stack output"
  type        = string
}

variable "cluster_admin_arns" {
  description = "IAM user/role ARNs that get cluster-admin (you). e.g. arn:aws:iam::123456789012:user/om"
  type        = list(string)
}

variable "ci_apply_role_arn" {
  description = "From bootstrap output tf_apply_role_arn. Gets cluster-admin so CI can manage helm releases."
  type        = string
}

variable "ci_plan_role_arn" {
  description = "From bootstrap output tf_plan_role_arn. Gets read-only (AdminView) cluster access."
  type        = string
}
