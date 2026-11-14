# ----------------------------------------------------------------------------
# Cluster-critical controllers installed by Terraform (they need IAM roles).
# Everything else (monitoring, apps) is deployed by ArgoCD from Git (GitOps).
#
# Chart versions are pinned on purpose. Bump them deliberately with
# `helm search repo <chart> --versions` — never float to "latest" in prod.
# ----------------------------------------------------------------------------
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.0"

  values = [yamlencode({
    clusterName  = module.eks.cluster_name
    region       = var.region
    vpcId        = module.vpc.vpc_id
    replicaCount = 2
    serviceAccount = {
      name = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.iam_role_arn
      }
    }
    nodeSelector = { workload = "system" }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.59.0" # appVersion 1.35.x: keep in lockstep with the cluster minor version

  values = [yamlencode({
    awsRegion = var.region
    autoDiscovery = {
      clusterName = module.eks.cluster_name
    }
    rbac = {
      serviceAccount = {
        name = "cluster-autoscaler"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.cluster_autoscaler_irsa.iam_role_arn
        }
      }
    }
    extraArgs = {
      balance-similar-node-groups = true
      skip-nodes-with-system-pods = false
      scale-down-unneeded-time    = "5m"
      expander                    = "least-waste"
    }
    nodeSelector = { workload = "system" }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.17.0"

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      name = "external-secrets"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.external_secrets_irsa.iam_role_arn
      }
    }
    nodeSelector = { workload = "system" }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.0.0"

  values = [yamlencode({
    global = {
      nodeSelector = { workload = "system" }
    }
    configs = {
      params = {
        "server.insecure" = true # TLS terminated at the ALB / use port-forward in dev
      }
    }
  })]

  depends_on = [module.eks]
}
