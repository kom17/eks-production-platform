# Run `make help` for the list of targets.
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

REGION   ?= ap-south-1
BOOT_DIR := terraform/bootstrap
DEV_DIR  := terraform/environments/dev
APP_DIR  := apps/sample-app
CLUSTER  ?= eks-platform-dev

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

# ---------------------------------------------------------------- setup ----
.PHONY: set-repo
set-repo: ## Point ArgoCD at your fork: make set-repo REPO=youruser/eks-production-platform
	@test -n "$(REPO)" || { echo "usage: make set-repo REPO=owner/name"; exit 1; }
	grep -rl 'YOUR_GITHUB_USER/eks-production-platform' gitops | xargs sed -i 's#YOUR_GITHUB_USER/eks-production-platform#$(REPO)#g'
	@echo "Updated gitops/ repoURLs to github.com/$(REPO)"

.PHONY: bootstrap
bootstrap: ## One-time: state bucket + GitHub OIDC roles. make bootstrap REPO=owner/name
	@test -n "$(REPO)" || { echo "usage: make bootstrap REPO=owner/name"; exit 1; }
	terraform -chdir=$(BOOT_DIR) init
	terraform -chdir=$(BOOT_DIR) apply -var="github_repo=$(REPO)"
	@echo; echo "Now copy these outputs into $(DEV_DIR)/terraform.tfvars and GitHub repo variables:"
	terraform -chdir=$(BOOT_DIR) output

# ----------------------------------------------------------- terraform ----
.PHONY: init
init: ## terraform init for dev (reads bucket name from bootstrap outputs)
	terraform -chdir=$(DEV_DIR) init -backend-config="bucket=$$(terraform -chdir=$(BOOT_DIR) output -raw state_bucket)"

.PHONY: plan
plan: ## terraform plan for dev
	terraform -chdir=$(DEV_DIR) plan -out=tfplan

.PHONY: apply
apply: ## terraform apply the saved dev plan (~15-20 min first time)
	terraform -chdir=$(DEV_DIR) apply tfplan

.PHONY: kubeconfig
kubeconfig: ## Point kubectl at the cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)

# ---------------------------------------------------------------- gitops ----
.PHONY: argocd-bootstrap
argocd-bootstrap: ## Apply the app-of-apps root once; ArgoCD takes over from here
	kubectl apply -f gitops/bootstrap/root-app.yaml
	@echo "Watch: kubectl -n argocd get applications -w"

.PHONY: argocd-ui
argocd-ui: ## ArgoCD UI on http://localhost:8080 (prints admin password)
	@echo "user: admin  password: $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	kubectl -n argocd port-forward svc/argocd-server 8080:80

.PHONY: grafana
grafana: ## Grafana on http://localhost:3000
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

.PHONY: app-url
app-url: ## Print the public ALB URL of the sample app
	@echo "http://$$(kubectl -n sample-app get ingress sample-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

# ------------------------------------------------------------------- app ----
.PHONY: test
test: ## Lint + unit tests for the sample app
	cd $(APP_DIR) && pip install -q -r requirements-dev.txt && ruff check src && pytest -q src

.PHONY: run-local
run-local: ## Build and run the app container locally on :8080
	docker build -t sample-app:local $(APP_DIR)
	docker run --rm -p 8080:8080 sample-app:local

.PHONY: lint
lint: ## fmt + validate + tflint, like CI
	terraform fmt -check -recursive terraform
	terraform -chdir=$(DEV_DIR) validate
	tflint --init --config $(CURDIR)/.tflint.hcl && tflint --recursive --config $(CURDIR)/.tflint.hcl

# --------------------------------------------------------------- teardown ----
# Order matters: ALBs and EBS volumes are created by controllers *inside* the
# cluster, so Terraform doesn't know about them. Destroying the VPC first would
# hang on the ALB's ENIs and leave orphaned (billable) resources behind.
.PHONY: destroy
destroy: ## Tear EVERYTHING down safely (k8s-created ALBs/EBS first, then Terraform)
	@read -p "Destroy cluster $(CLUSTER) and all workloads? Type the cluster name: " c && [ "$$c" = "$(CLUSTER)" ]
	-kubectl -n argocd delete application root --wait=true --timeout=10m
	@echo "Waiting for ALBs to be deleted by the load balancer controller..."
	@for i in $$(seq 1 30); do \
	  n=$$(aws elbv2 describe-load-balancers --region $(REGION) --query "length(LoadBalancers[?contains(LoadBalancerName, 'k8s-')])" --output text); \
	  [ "$$n" = "0" ] && break; echo "  $$n ALB(s) left"; sleep 10; done
	-kubectl delete pvc --all -A --wait=true --timeout=5m
	terraform -chdir=$(DEV_DIR) destroy
	@echo "Done. Bootstrap stack (state bucket, OIDC) is kept; it costs ~nothing."
