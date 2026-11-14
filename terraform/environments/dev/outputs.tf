output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.sample_app.repository_url
}

output "app_ci_role_arn" {
  description = "Set as GitHub secret AWS_APP_CI_ROLE_ARN"
  value       = aws_iam_role.app_ci.arn
}

output "external_secrets_role_arn" {
  value = module.external_secrets_irsa.iam_role_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
