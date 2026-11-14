# Runbook

## Daily checks
```bash
kubectl get nodes -L workload,eks.amazonaws.com/capacityType,topology.kubernetes.io/zone
kubectl -n argocd get applications            # all Synced / Healthy?
kubectl get pods -A | grep -vE 'Running|Completed'
```

## Deploy / rollback
- **Deploy:** merge to `main`. CI bumps `apps/sample-app/k8s/overlays/dev/kustomization.yaml` and ArgoCD syncs within about 3 minutes (or click *Refresh*).
- **Rollback:** `git revert <deploy commit>` and push. ArgoCD rolls back. Don't `kubectl rollout undo`, because self-heal will revert it to whatever Git says.
- **Watch a rollout:** `kubectl -n sample-app rollout status deploy/sample-app`

## Troubleshooting

| Symptom | Check | Usual cause |
|---|---|---|
| Pod `ImagePullBackOff` | `kubectl -n sample-app describe pod` | First deploy before CI pushed an image (overlay still has the placeholder account ID), or wrong tag |
| Pod `Pending` | `kubectl describe pod` events; `kubectl -n kube-system logs deploy/cluster-autoscaler` | Node group at `max_size`, or no Spot capacity for the listed types |
| Pod rejected: *violates PodSecurity "restricted"* | Namespace events | Missing `securityContext` fields: compare with `k8s/base/deployment.yaml` |
| Ingress has no address | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` | Subnet tags missing, or IRSA role not annotated |
| 502s during deploys | ALB target group health, `preStop` present? | Pod removed before ALB deregistered: see ADR-009 |
| ExternalSecret `SecretSyncedError` | `kubectl describe externalsecret` | Secret name not under `eks-platform-dev/` prefix (IAM scope) |
| ArgoCD app `OutOfSync` loop | App diff in UI | A controller mutates a field: add `ignoreDifferences` |
| `terraform plan` fails on `helm_release` in CI | Job log | Plan role missing EKS access entry, or cluster not reachable (check `admin_cidrs`) |

## Simulate failures (great for demos)
```bash
# Self-heal: ArgoCD reverts manual drift
kubectl -n sample-app scale deploy/sample-app --replicas=1 && kubectl -n sample-app get deploy -w

# Autoscaling: generate load and watch HPA, then Cluster Autoscaler
kubectl -n sample-app run load --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -qO- http://sample-app >/dev/null; done'
kubectl -n sample-app get hpa -w

# Node failure / Spot interruption: drain a node and verify zero downtime via the PDB
kubectl drain <apps-node> --ignore-daemonsets --delete-emptydir-data
```

## Secrets
```bash
aws secretsmanager create-secret --name eks-platform-dev/sample-app \
  --secret-string '{"API_KEY":"example"}'
kubectl apply -f docs/examples/external-secret.yaml
kubectl -n sample-app get secret sample-app-secrets
```

## Upgrades
- **EKS:** bump `kubernetes_version` one minor version at a time. Control plane first, then managed node groups (rolling, respects PDBs), then add-ons (`most_recent = true`).
- **Helm add-ons:** bump the pinned `version` in `addons.tf` via a PR and read the chart changelog first.
- **Monitoring stack:** bump `targetRevision` in `gitops/apps/kube-prometheus-stack.yaml`.

## Teardown
```bash
make destroy
```
**Why the order matters:** the ALB (from the Ingress) and the EBS volumes (from PVCs) are created by controllers *inside* the cluster, so Terraform doesn't know they exist. If you run `terraform destroy` first:
1. The VPC deletion hangs on the ALB's network interfaces, and
2. the ALB, its target groups and the EBS volumes keep billing after the cluster is gone.

`make destroy` deletes the ArgoCD root app (the cascade finalizers remove all child resources), waits for the ALBs to disappear, deletes leftover PVCs, and *then* runs `terraform destroy`.

If something was left behind, check: EC2 → Load Balancers / Target Groups / Volumes, filtered by tag `elbv2.k8s.aws/cluster` or `kubernetes.io/cluster/eks-platform-dev`.
