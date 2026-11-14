# Architecture Decision Records

Short records of *why* things are the way they are. Format: context → decision → consequences.

---

## ADR-001: Custom VPC module instead of the community module
**Context.** `terraform-aws-modules/vpc` is excellent, but it hides the networking underneath EKS.
**Decision.** Write a small VPC module by hand: 3 AZs, `/20` subnets carved with `cidrsubnet()`, public subnets for ALB/NAT, and private subnets for nodes and pods. Subnets are tagged for ELB discovery.
**Consequences.** More code to maintain, but every route table and tag is explicit and explainable. The community modules are still used for EKS and IAM, where re-implementing adds no learning value.

## ADR-002: Single NAT gateway in dev
**Context.** A NAT gateway costs ~$33/month plus data charges, and one per AZ triples that.
**Decision.** `single_nat_gateway = true` in dev. The module supports one per AZ via a flag.
**Consequences.** An AZ outage that takes down the NAT's AZ breaks egress from every AZ. That's acceptable for dev and **not** for prod. An S3 gateway endpoint (free) keeps ECR layer pulls off the NAT.

## ADR-003: EKS access entries, explicit admins, creator-admin disabled
**Context.** `enable_cluster_creator_admin_permissions = true` grants admin to *whoever runs apply*. When the same stack is applied from a laptop and from CI, the "creator" changes and the access entry gets rewritten, which can lock out the other identity.
**Decision.** Use API authentication mode with explicit `access_entries`: humans plus the CI apply role get `ClusterAdmin`, and the CI plan role gets `AdminView`, which is read-only but can read Secrets because Helm stores release state there.
**Consequences.** Deterministic access, no `aws-auth` ConfigMap to corrupt, and an audit trail in IAM.

## ADR-004: GitHub OIDC with split plan and apply roles
**Context.** Long-lived AWS keys in CI secrets are the #1 cloud credential leak vector.
**Decision.** Use the GitHub OIDC provider with three roles:
- `terraform-plan`: `ReadOnlyAccess` plus state access. Trusted for any ref in this repo, so PRs can plan.
- `terraform-apply`: trusted **only** for `environment:production`, which requires a human approval.
- `app-ci`: trusted only for `refs/heads/main`, and can push to exactly one ECR repository.

**Consequences.** A malicious PR can at most *read*. The apply role is `AdministratorAccess` (accepted trade-off in a personal account). In an organization it would be scoped down, or given a permissions boundary that blocks IAM escalation.

## ADR-005: Terraform installs only "cluster-critical" add-ons; ArgoCD owns the rest
**Context.** Some add-ons need IAM roles created in the same Terraform run (LB controller, autoscaler, External Secrets), and ArgoCD itself must exist before GitOps can start.
**Decision.** Terraform installs the controllers that need IRSA, plus ArgoCD. Everything else (monitoring, platform config, apps) is ArgoCD Applications in Git.
**Consequences.** There is a clean boundary: Terraform handles AWS and bootstrap, Git and ArgoCD handle in-cluster state. Upgrading monitoring is a PR, not a `terraform apply`.

## ADR-006: GitOps pull model; CI never touches the cluster
**Context.** Push-based CD (`kubectl apply` from CI) needs cluster-admin credentials in CI and gives no drift detection.
**Decision.** CI pushes the image and commits the new tag to the Kustomize overlay. ArgoCD (auto-sync, self-heal, prune) reconciles.
**Consequences.** Git history *is* the deployment history, so a rollback is `git revert`. Manual `kubectl edit` drift is reverted automatically. The deploy commit needs push rights to `main` (with branch protection, allow the Actions bot or use a GitHub App token).

## ADR-007: Spot for apps, on-demand for the platform
**Context.** Spot is about 70% cheaper but can be reclaimed with 2 minutes' notice.
**Decision.** The `system` node group is on-demand and runs ArgoCD, controllers and Prometheus. The `apps` node group is Spot across 4 instance types (fewer simultaneous interruptions) and runs stateless workloads. Workloads land on the right group via `nodeSelector: workload=...`.
**Consequences.** App resilience comes from ≥2 replicas, a PDB, topology spread across AZs and nodes, and graceful shutdown.

## ADR-008: Memory limits, no CPU limits
**Context.** CPU limits cause CFS throttling, which raises latency even when the node has idle CPU.
**Decision.** Set CPU *requests* (for scheduling and HPA) and memory requests and limits. Don't set CPU limits.
**Consequences.** Better tail latency. Noisy-neighbor risk is bounded by requests-based scheduling. This is an intentional, commonly debated choice, so expect a follow-up question in interviews.

## ADR-009: Zero-downtime rollout mechanics
**Decision.** Use `maxUnavailable: 0`, a readiness probe, a `preStop` sleep of 15s (the ALB deregisters the pod before SIGTERM), uvicorn graceful shutdown of 20s, `terminationGracePeriodSeconds: 45`, ALB `deregistration_delay` of 10s, and `target-type: ip`.
**Why.** Without the preStop delay, the ALB keeps sending traffic to a pod that is already shutting down, which causes 502s during deploys and node drains.

## ADR-010: Network policy enforced by the VPC CNI
**Decision.** Enable `enableNetworkPolicy` on the vpc-cni add-on rather than installing Calico.
**Consequences.** One less component to run. The NetworkPolicy allows only VPC CIDR traffic (ALB) and the `monitoring` namespace on port 8080.

## ADR-011: Pinned tool versions; Trivy as a container image, not the GitHub Action
**Context.** In March 2026 the `aquasecurity/trivy-action` tags were compromised and republished (supply-chain attack, similar to `tj-actions/changed-files` in 2025).
**Decision.** Pin every tool to an exact version (Terraform, tflint, checkov, kubeconform, Trivy, Helm charts, Python deps). Run Trivy from its pinned container image.
**Consequences.** Upgrades are deliberate PRs. **Next hardening step:** pin third-party actions by commit SHA and let Dependabot bump them.

## ADR-012: Native S3 state locking (no DynamoDB)
**Decision.** `use_lockfile = true` (Terraform ≥ 1.10). The state bucket is versioned, KMS-encrypted, TLS-only, has public access blocked and uses `prevent_destroy`.
**Consequences.** One fewer resource. DynamoDB-based locking is deprecated.
