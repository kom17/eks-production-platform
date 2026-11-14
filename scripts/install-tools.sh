#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Installs everything this project needs on Ubuntu / WSL (x86_64).
#   sudo bash scripts/install-tools.sh
#
# Versions are pinned to match CI. Every binary download is checked against
# the vendor's published SHA256 checksum before it's installed.
# Safe to re-run (re-installs the pinned versions).
# -----------------------------------------------------------------------------
set -euo pipefail

TERRAFORM_VERSION="1.17.1"   # same as .github/workflows/terraform.yml
KUBECTL_VERSION="v1.35.10"   # matches cluster version 1.35 (kubectl supports +/-1 minor)
TFLINT_VERSION="v0.65.0"     # same as CI
GH_VERSION="2.103.3"         # GitHub CLI, used to create the repo and push

[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo bash $0"; exit 1; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "This script is for x86_64 only"; exit 1; }
REAL_USER="${SUDO_USER:-root}"

TMP="$(mktemp -d -p /var/tmp)" # on disk: /tmp is a small RAM tmpfs on WSL
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

step "apt packages (make, unzip, jq, python venv/pip, pipx)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  make unzip curl ca-certificates git jq gnupg python3-pip python3-venv pipx

step "AWS CLI v2"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip
./aws/install --update

step "Terraform ${TERRAFORM_VERSION}"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
grep "linux_amd64.zip" "terraform_${TERRAFORM_VERSION}_SHA256SUMS" | sha256sum -c -
unzip -oq "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" terraform
install -m 0755 terraform /usr/local/bin/terraform

step "kubectl ${KUBECTL_VERSION}"
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -
install -m 0755 kubectl /usr/local/bin/kubectl

step "tflint ${TFLINT_VERSION}"
curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip"
curl -fsSLO "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/checksums.txt"
grep " tflint_linux_amd64.zip$" checksums.txt | sha256sum -c -
unzip -oq tflint_linux_amd64.zip tflint
install -m 0755 tflint /usr/local/bin/tflint

step "GitHub CLI ${GH_VERSION}"
GH_TAR="gh_${GH_VERSION}_linux_amd64.tar.gz"
curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_TAR}"
curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt"
grep " ${GH_TAR}$" "gh_${GH_VERSION}_checksums.txt" | sha256sum -c -
tar xzf "$GH_TAR"
install -m 0755 "gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh

step "pre-commit (via pipx, for user ${REAL_USER})"
sudo -u "$REAL_USER" -H pipx install --force pre-commit
sudo -u "$REAL_USER" -H pipx ensurepath >/dev/null

step "Installed versions"
aws --version
terraform version | head -1
kubectl version --client | head -1
tflint --version | head -1
gh --version | head -1
make --version | head -1
python3 --version
sudo -u "$REAL_USER" -H bash -lc 'command -v pre-commit >/dev/null && pre-commit --version || echo "pre-commit: open a new terminal to get it on PATH"'

printf '\n\033[1;32mAll tools installed.\033[0m Next: run `aws configure` and `gh auth login` (see README).\n'
