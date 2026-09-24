#!/usr/bin/env bash
# scripts/azure-create-vm.sh
# Creates an Azure VM that installs and runs Fleetbase with Docker Compose.
# -------------------------------------------------------
# Needs the Azure CLI, logged in (`az login`). Everything is created in one
# resource group, so `az group delete -n <group>` removes all of it.
#
# Usage:
#   bash scripts/azure-create-vm.sh --location westeurope
#   bash scripts/azure-create-vm.sh --location westeurope --size Standard_B2ms --dns-label my-fleetbase
#   bash scripts/azure-create-vm.sh --help
#
# What it creates:
#   - a resource group
#   - a network security group: SSH from your IP only; 4200 (console), 8000 (API)
#     and 38000 (websockets) from anywhere. MySQL (3306) stays closed.
#   - a static public IP, so the address baked into the install survives a stop/start
#   - an Ubuntu 24.04 VM that, on first boot, adds swap, installs Docker, clones the
#     repository and runs scripts/docker-install.sh --non-interactive on its public address
#
# Fleetbase is served over plain HTTP (development mode). HTTPS needs a domain and a
# certificate; see the notes printed at the end.
# -------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}ℹ  ${RESET}$*"; }
success() { echo -e "${GREEN}✔  ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${RESET}$*"; }
error()   { echo -e "${RED}✖  ${RESET}$*" >&2; }
section() { echo -e "\n${BOLD}── $* $(printf '─%.0s' {1..40})${RESET}"; }

# ─── Defaults (each can also be set as an environment variable) ──────────────
RESOURCE_GROUP="${RESOURCE_GROUP:-fleetbase-rg}"
LOCATION="${LOCATION:-}"
VM_NAME="${VM_NAME:-fleetbase-vm}"
VM_SIZE="${VM_SIZE:-Standard_B2s}"
DISK_SIZE_GB="${DISK_SIZE_GB:-64}"
ADMIN_USER="${ADMIN_USER:-azureuser}"
SSH_KEY="${SSH_KEY:-}"
SSH_SOURCE="${SSH_SOURCE:-}"
DNS_LABEL="${DNS_LABEL:-}"
REPO_URL="${REPO_URL:-https://github.com/mamatsalay/fleetbase.git}"
BRANCH="${BRANCH:-main}"
SWAP_GB="${SWAP_GB:-4}"
AUTO_SHUTDOWN="${AUTO_SHUTDOWN:-}"
WAIT_MINUTES="${WAIT_MINUTES:-45}"
IMAGE="Canonical:ubuntu-24_04-lts:server:latest"

usage() {
  cat <<USAGE
Usage: bash scripts/azure-create-vm.sh --location <region> [options]

  -l, --location <region>     Azure region, e.g. westeurope, germanywestcentral (required)
  -g, --resource-group <name> Resource group to create             [${RESOURCE_GROUP}]
  -n, --name <name>           VM name                              [${VM_NAME}]
  -s, --size <sku>            VM size; 4 GB RAM is the minimum     [${VM_SIZE}]
      --disk <GB>             OS disk size                         [${DISK_SIZE_GB}]
  -u, --admin-user <name>     SSH user                             [${ADMIN_USER}]
  -k, --ssh-key <path>        Public key to install      [~/.ssh/id_ed25519.pub or id_rsa.pub,
                                                          generated if neither exists]
      --ssh-source <cidr>     Who may SSH in             [your current public IP]
      --dns-label <label>     Also give the IP a name: <label>.<region>.cloudapp.azure.com,
                              used as the Fleetbase host instead of the bare IP
      --repo <url>            Repository to deploy                 [${REPO_URL}]
      --branch <name>         Branch to deploy                     [${BRANCH}]
      --auto-shutdown <HHMM>  Stop the VM daily at this UTC time to save credit (e.g. 2200)
      --no-wait               Don't wait for the console to come up
  -h, --help                  Show this help

Every option can also be given as an environment variable (LOCATION, VM_SIZE, BRANCH, ...).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--location)       LOCATION="$2"; shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -n|--name)           VM_NAME="$2"; shift 2 ;;
    -s|--size)           VM_SIZE="$2"; shift 2 ;;
    --disk)              DISK_SIZE_GB="$2"; shift 2 ;;
    -u|--admin-user)     ADMIN_USER="$2"; shift 2 ;;
    -k|--ssh-key)        SSH_KEY="$2"; shift 2 ;;
    --ssh-source)        SSH_SOURCE="$2"; shift 2 ;;
    --dns-label)         DNS_LABEL="$2"; shift 2 ;;
    --repo)              REPO_URL="$2"; shift 2 ;;
    --branch)            BRANCH="$2"; shift 2 ;;
    --auto-shutdown)     AUTO_SHUTDOWN="$2"; shift 2 ;;
    --no-wait)           WAIT_MINUTES=0; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

###############################################################################
# Pre-flight
###############################################################################
section "Pre-flight Checks"

if [[ -z "$LOCATION" ]]; then
  error "Choose a region with --location (see: az account list-locations -o table)."
  exit 1
fi

if ! command -v az >/dev/null 2>&1; then
  error "The Azure CLI is required: https://learn.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi
success "Azure CLI found"

if ! SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null); then
  error "Not logged in. Run 'az login' and retry."
  exit 1
fi
success "Subscription: ${SUBSCRIPTION}"

if [[ -z "$SSH_KEY" ]]; then
  for candidate in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
    [[ -f "$candidate" ]] && { SSH_KEY="$candidate"; break; }
  done
fi
if [[ -n "$SSH_KEY" ]]; then
  [[ -f "$SSH_KEY" ]] || { error "SSH public key not found: $SSH_KEY"; exit 1; }
  SSH_KEY_ARGS=(--ssh-key-values "$SSH_KEY")
  success "SSH key: ${SSH_KEY}"
else
  SSH_KEY_ARGS=(--generate-ssh-keys)
  info "No SSH key found; Azure CLI will generate one in ~/.ssh"
fi

if [[ -z "$SSH_SOURCE" ]]; then
  if MY_IP=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null) && [[ "$MY_IP" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    SSH_SOURCE="${MY_IP}/32"
    success "SSH will be allowed from your IP only: ${SSH_SOURCE}"
  else
    SSH_SOURCE="*"
    warn "Could not detect your public IP; SSH will be open to everyone. Pass --ssh-source to restrict it."
  fi
fi

if [[ -n "$AUTO_SHUTDOWN" && ! "$AUTO_SHUTDOWN" =~ ^([01][0-9]|2[0-3])[0-5][0-9]$ ]]; then
  error "--auto-shutdown takes a UTC time as HHMM, e.g. 2200."
  exit 1
fi

NSG_NAME="${VM_NAME}-nsg"
IP_NAME="${VM_NAME}-ip"

###############################################################################
# Network
###############################################################################
section "Resource Group and Network"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
success "Resource group ${RESOURCE_GROUP} (${LOCATION})"

az network nsg create --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME" --location "$LOCATION" --output none
az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
  --name AllowSSH --priority 1000 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "$SSH_SOURCE" --destination-port-ranges 22 --output none
az network nsg rule create --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
  --name AllowFleetbase --priority 1010 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes Internet --destination-port-ranges 4200 8000 38000 --output none
success "Firewall ${NSG_NAME}: SSH from ${SSH_SOURCE}; 4200, 8000, 38000 open; 3306 closed"

IP_ARGS=(--resource-group "$RESOURCE_GROUP" --name "$IP_NAME" --location "$LOCATION" --sku Standard --allocation-method Static --output none)
[[ -n "$DNS_LABEL" ]] && IP_ARGS+=(--dns-name "$DNS_LABEL")
az network public-ip create "${IP_ARGS[@]}"

PUBLIC_IP=$(az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$IP_NAME" --query ipAddress -o tsv)
FLEETBASE_HOST="$PUBLIC_IP"
if [[ -n "$DNS_LABEL" ]]; then
  FLEETBASE_HOST=$(az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$IP_NAME" --query dnsSettings.fqdn -o tsv)
fi
success "Static public IP ${PUBLIC_IP}${DNS_LABEL:+ (${FLEETBASE_HOST})}"

###############################################################################
# First-boot script
###############################################################################
CLOUD_INIT=$(mktemp)
trap 'rm -f "$CLOUD_INIT"' EXIT

# Values are expanded here, on your machine; everything else runs on the VM as root.
cat > "$CLOUD_INIT" <<CLOUD_INIT
#!/bin/bash
set -euxo pipefail
exec > >(tee -a /var/log/fleetbase-install.log) 2>&1

ADMIN_USER=$(printf '%q' "$ADMIN_USER")
REPO_URL=$(printf '%q' "$REPO_URL")
BRANCH=$(printf '%q' "$BRANCH")
SWAP_GB=$(printf '%q' "$SWAP_GB")
export FLEETBASE_HOST=$(printf '%q' "$FLEETBASE_HOST")
CLOUD_INIT
cat >> "$CLOUD_INIT" <<'CLOUD_INIT'

# Building the console needs more memory than a 4 GB VM has free.
if [[ "$SWAP_GB" -gt 0 ]] && ! swapon --show | grep -q /swapfile; then
  fallocate -l "${SWAP_GB}G" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git openssl curl
curl -fsSL https://get.docker.com | sh
usermod -aG docker "$ADMIN_USER"

APP_DIR="/home/${ADMIN_USER}/fleetbase"
git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"
bash scripts/docker-install.sh --non-interactive
chown -R "${ADMIN_USER}:${ADMIN_USER}" "$APP_DIR"

touch /var/log/fleetbase-install.done
CLOUD_INIT

###############################################################################
# VM
###############################################################################
section "Virtual Machine"
info "Creating ${VM_NAME} (${VM_SIZE}, ${DISK_SIZE_GB} GB Standard SSD). This takes a few minutes..."

if ! az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --location "$LOCATION" \
  --image "$IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  "${SSH_KEY_ARGS[@]}" \
  --public-ip-address "$IP_NAME" \
  --nsg "$NSG_NAME" \
  --os-disk-size-gb "$DISK_SIZE_GB" \
  --storage-sku StandardSSD_LRS \
  --custom-data "$CLOUD_INIT" \
  --output none; then
  error "VM creation failed. If the size isn't available in ${LOCATION} for your subscription, list the options:"
  error "  az vm list-skus --location ${LOCATION} --resource-type virtualMachines --query \"[?starts_with(name,'Standard_B')].name\" -o tsv"
  error "then rerun with --size <sku> or another --location. Clean up first with: az group delete -n ${RESOURCE_GROUP}"
  exit 1
fi
success "VM ${VM_NAME} is running"

if [[ -n "$AUTO_SHUTDOWN" ]]; then
  az vm auto-shutdown --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --time "$AUTO_SHUTDOWN" --output none
  success "The VM will stop every day at ${AUTO_SHUTDOWN} UTC"
fi

###############################################################################
# Wait for Fleetbase
###############################################################################
CONSOLE_URL="http://${FLEETBASE_HOST}:4200"
SSH_CMD="ssh ${ADMIN_USER}@${PUBLIC_IP}"

if [[ "$WAIT_MINUTES" -gt 0 ]]; then
  section "Installing Fleetbase on the VM"
  info "Docker, the images and the console build take 15-30 minutes. Waiting up to ${WAIT_MINUTES} minutes."
  info "Follow along in another terminal: ${SSH_CMD} tail -f /var/log/fleetbase-install.log"
  SECONDS=0
  until curl -fsS --max-time 10 -o /dev/null "$CONSOLE_URL"; do
    if (( SECONDS >= WAIT_MINUTES * 60 )); then
      warn "The console isn't answering yet. Check the install log: ${SSH_CMD} tail -n 100 /var/log/fleetbase-install.log"
      break
    fi
    sleep 30
  done
fi

###############################################################################
# Summary
###############################################################################
echo
printf '%0.s═' {1..60}; echo
echo -e "  ${BOLD}☁️   Fleetbase on Azure${RESET}"
printf '%0.s═' {1..60}; echo
echo
echo "  📍  Console → ${CONSOLE_URL}"
echo "      API     → http://${FLEETBASE_HOST}:8000"
echo "      SSH     → ${SSH_CMD}"
echo "      Log     → /var/log/fleetbase-install.log (done when /var/log/fleetbase-install.done exists)"
echo
echo "  💳  Saving credit"
echo "      Stop:   az vm deallocate -g ${RESOURCE_GROUP} -n ${VM_NAME}"
echo "      Start:  az vm start -g ${RESOURCE_GROUP} -n ${VM_NAME}"
echo "      Delete everything: az group delete -n ${RESOURCE_GROUP}"
echo "      A stopped (deallocated) VM costs only its disk and static IP."
echo
echo "  🔄  Updating after new commits"
echo "      ${SSH_CMD}"
echo "      cd fleetbase && git pull && docker compose up -d --build console"
echo
echo "  🔒  HTTPS needs a domain pointing at ${PUBLIC_IP} and a certificate; until then"
echo "      Fleetbase runs over plain HTTP."
printf '%0.s═' {1..60}; echo
echo
