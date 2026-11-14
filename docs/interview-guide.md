# How to present this project

> **Rule #1:** Only claim what you have deployed yourself and can explain without notes. Interviewers at the ₹15–25 LPA level *will* drill down two or three levels deep. Deploy it at least twice, break it on purpose (see [runbook → simulate failures](runbook.md#simulate-failures-great-for-demos)), and take screenshots.

---

## 30-second pitch
> "I built a production-style EKS platform end-to-end. Terraform provisions a custom 3-AZ VPC and an EKS cluster with Spot and on-demand node groups, and each controller gets its own IRSA role. GitHub Actions uses OIDC, so there are no AWS keys anywhere. Infra PRs get fmt, tflint, checkov and a plan comment, and apply needs a manual approval. App changes are tested, scanned with Trivy, pushed to ECR, and then CI commits the new tag to Git, which ArgoCD rolls out with zero downtime. It has Prometheus alerts on error rate and latency, HPA plus Cluster Autoscaler, pods hardened to the `restricted` Pod Security Standard, and a teardown that cleans up the ALBs and EBS volumes Terraform doesn't know about."

## 2-minute walkthrough (draw this on the whiteboard)
1. **Network:** VPC, public subnets (ALB, NAT), private subnets (nodes), S3 endpoint.
2. **Cluster:** EKS, two node groups (why Spot for apps), access entries, IRSA.
3. **Pipelines:** Infra pipeline (plan on PR, approved apply) vs app pipeline (build, scan, push, Git commit).
4. **GitOps:** ArgoCD app-of-apps, sync waves, self-heal. Rollback = `git revert`.
5. **Day-2 operations:** Monitoring and alerts, autoscaling, secrets, upgrades, cost, teardown.

---

## Resume bullets (adapt numbers to what *you* measured)
- Designed and provisioned a production-grade **AWS EKS platform with Terraform** (custom 3-AZ VPC module, managed Spot and on-demand node groups, IRSA), cutting compute cost by **~70%** for stateless workloads with Spot.
- Eliminated long-lived cloud credentials by implementing **GitHub Actions → AWS OIDC** with separate least-privilege plan and apply roles and an approval-gated production environment.
- Built a **GitOps delivery pipeline** (GitHub Actions + ArgoCD app-of-apps) with Trivy image scanning, SBOM generation and kubeconform validation, enabling **zero-downtime rolling deployments** and `git revert` rollbacks.
- Hardened workloads to the Kubernetes **`restricted` Pod Security Standard** with default-deny NetworkPolicies, read-only root filesystems and non-root containers. Shifted IaC security left with **checkov and tflint** in CI.
- Implemented observability with **Prometheus/Grafana** (ServiceMonitors, SLO-based alerts on error rate and p95 latency) and autoscaling with **HPA + Cluster Autoscaler**.

Put the GitHub link on the resume and pin the repo. Add 3–4 screenshots to the README: ArgoCD app tree, Grafana dashboard, a PR with a plan comment, and `kubectl get nodes` showing Spot.

---

## Questions you should be ready for

**Networking**
- *Why do pods get VPC IPs? What's prefix delegation?* VPC CNI assigns real ENI IPs. Prefix delegation assigns /28 prefixes per ENI slot, so a node can run many more pods (useful on small instances).
- *What happens if the NAT's AZ goes down?* With a single NAT, all private egress breaks (ADR-002). The prod answer is one NAT per AZ.
- *Why `target-type: ip`?* The ALB routes directly to pod IPs, which skips the NodePort/kube-proxy hop, gives more accurate health checks, and is required for Fargate.

**Security**
- *How does IRSA work?* The pod gets a projected ServiceAccount JWT. The AWS SDK calls `AssumeRoleWithWebIdentity`, and the IAM trust policy checks the OIDC issuer and the `sub = system:serviceaccount:ns:name` claim. *EKS Pod Identity* is the newer alternative (the agent add-on is already installed here). Know the difference.
- *How does GitHub OIDC trust work, and what stops a fork PR from applying?* The `sub` claim condition: the apply role only accepts `repo:X:environment:production`, and that environment requires approval.
- *Why is the apply role admin? How would you fix it?* Permissions boundary, scoped policies per resource type, or a separate account per environment. See ADR-004.
- *A secret leaked. What do you do?* Rotate in Secrets Manager; ESO refreshes it (`refreshInterval`). Restart pods if the app reads env vars only at startup.

**Kubernetes**
- *Liveness vs readiness vs startup probes?* What happens if liveness checks a dependency (cascading restarts)?
- *Why no CPU limits?* CFS throttling (ADR-008). What's the counter-argument?
- *Walk me through a zero-downtime deploy.* Cover `maxUnavailable: 0`, readiness gating, preStop sleep, and ALB deregistration (ADR-009).
- *HPA scaled up but pods are Pending. What happens next?* Cluster Autoscaler sees unschedulable pods, simulates scheduling, scales the ASG, and the node joins (2–4 min). Why is Karpenter faster? It provisions instances directly, without ASGs.
- *What does a PDB protect against, and what doesn't it?* Voluntary disruptions (drain, upgrade) yes; node crashes and Spot reclaims no.

**GitOps and CI/CD**
- *Why GitOps over `kubectl apply` in CI?* No cluster creds in CI, drift detection and self-heal, and Git as the audit log (ADR-006).
- *How do you promote from dev to prod?* Add an overlay per environment, and promote via a PR that copies the image tag. Progressive delivery with Argo Rollouts.
- *Two merges land at once. Do the tag bumps race?* The concurrency group plus the rebase-retry loop in `app-ci.yml`.

**Terraform**
- *How is state locked? What if a lock gets stuck?* `use_lockfile` with S3 conditional writes. `terraform force-unlock <id>` after confirming nobody is running.
- *Why re-plan in the apply job?* State may have changed between the PR plan and the approval.
- *How would you split this for multiple environments or accounts?* `environments/<env>` directories with their own state keys, modules shared, and Terragrunt or workspaces as alternatives (trade-offs).

**Cost**
- *What does this cost and how did you reduce it?* Walk through the README cost table, then Spot, single NAT, the S3 endpoint, gp3, and ECR lifecycle.

**Supply chain**
- *How do you trust third-party GitHub Actions?* Pin by SHA, minimal `permissions:`, and Dependabot. Read up on the `tj-actions/changed-files` (2025) and `trivy-action` (2026) incidents. ADR-011 explains why Trivy runs as a pinned image here.

---

## Salary negotiation pointers
- With 2.5 YOE, target **Senior/SDE-2 Cloud, DevOps or Platform Engineer** roles. Product companies and well-funded startups pay the most for this exact skill set (EKS + Terraform + GitOps).
- Get **2–3 offers in parallel**. Competing offers are the strongest lever.
- Don't anchor on your current CTC. Answer with your expected range for the *role*.
- Certifications that pair well with this project: **AWS SAA-C03** (baseline), **CKA** (shows real Kubernetes depth), and optionally the HashiCorp **Terraform Associate**.
