locals {
  name = "${var.project}-${var.environment}"

  cluster_admin_policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  # AdminView = read everything incl. Secrets (helm stores release state in Secrets,
  # so `terraform plan` on helm_release needs it). Still read-only.
  cluster_view_policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_entries = merge(
    { for i, arn in concat(var.cluster_admin_arns, [var.ci_apply_role_arn]) : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = { policy_arn = local.cluster_admin_policy, access_scope = { type = "cluster" } }
      }
    } },
    {
      ci-plan = {
        principal_arn = var.ci_plan_role_arn
        policy_associations = {
          view = { policy_arn = local.cluster_view_policy, access_scope = { type = "cluster" } }
        }
      }
    }
  )

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repo        = var.github_repo
  }
}

# ----------------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  region             = var.region
  cluster_name       = local.name
  cidr               = var.vpc_cidr
  az_count           = 3
  single_nat_gateway = true # dev: save ~$65/month. prod: false
  enable_flow_logs   = true
  tags               = local.tags
}

# ----------------------------------------------------------------------------
# EKS cluster
# ----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.admin_cidrs
  cluster_endpoint_private_access      = true

  # Access entries (modern replacement for aws-auth ConfigMap).
  # Creator-admin is OFF on purpose: with it on, whoever runs `apply` (your
  # laptop vs. the CI role) becomes "the creator", and switching between them
  # rewrites the access entry. Explicit entries are deterministic.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = local.access_entries

  # Control-plane audit logging
  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 14

  # Secrets envelope-encrypted with a KMS key created by the module
  # (module default: create_kms_key = true, encrypts "secrets")

  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  cluster_addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true" # enforce Kubernetes NetworkPolicies natively
        env = {
          ENABLE_PREFIX_DELEGATION = "true" # more pods per node
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    # Stable on-demand nodes for platform components (ArgoCD, controllers, monitoring)
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = { workload = "system" }
    }

    # Cheap spot nodes for application workloads; multiple types = fewer interruptions
    apps = {
      ami_type = "AL2023_x86_64_STANDARD"
      # Nitro-based types only (required for VPC CNI prefix delegation)
      instance_types = ["t3.medium", "t3a.medium", "t3.large", "t3a.large"]
      capacity_type  = "SPOT"
      min_size       = 1
      max_size       = 5
      desired_size   = 1

      labels = { workload = "apps" }
      # EKS managed node groups auto-tag their ASGs with
      # k8s.io/cluster-autoscaler/{enabled,<cluster>} for autoscaler discovery.
    }
  }

  tags = local.tags
}

# ----------------------------------------------------------------------------
# ECR repository for the sample app
# ----------------------------------------------------------------------------
resource "aws_ecr_repository" "sample_app" {
  name                 = "${local.name}/sample-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "sample_app" {
  repository = aws_ecr_repository.sample_app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
