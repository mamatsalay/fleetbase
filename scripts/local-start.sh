#!/usr/bin/env bash
# scripts/local-start.sh
# Runs Fleetbase on this computer (macOS or Linux) with Docker.
# -------------------------------------------------------
# Usage (from anywhere inside the repository):
#   bash scripts/local-start.sh            # first run installs, later runs just start it
#   bash scripts/local-start.sh --rebuild  # after `git pull`: rebuild the API and console, migrate
#   bash scripts/local-start.sh --stop     # stop the containers (data is kept)
#   bash scripts/local-start.sh --reset    # delete the install and its database, start over
#
# Until the database exists, runs call scripts/docker-install.sh --non-interactive, which
# generates the database credentials and docker-compose.override.yml. Once it exists they
# never call it again: new credentials would no longer match the existing database.
#
# The API image (fleetbase/fleetbase-api:latest) is built from this repository rather than
# pulled from Docker Hub, so the backend has exactly the extensions api/composer.json lists.
# Set GITHUB_AUTH_KEY to a GitHub token if Composer hits GitHub's download rate limit.
# -------------------------------------------------------
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}ℹ  ${RESET}$*"; }
success() { echo -e "${GREEN}✔  ${RESET}$*"; }
warn()    { echo -e "${YELLOW}⚠  ${RESET}$*"; }
error()   { echo -e "${RED}✖  ${RESET}$*" >&2; }
section() { echo -e "\n${BOLD}── $* $(printf '─%.0s' {1..40})${RESET}"; }

CONSOLE_URL="http://localhost:4200"
API_URL="http://localhost:8000"
WAIT_MINUTES="${WAIT_MINUTES:-40}"
MIN_MEMORY_GB=4
RECOMMENDED_MEMORY_GB=6
OVERRIDE_FILE="docker-compose.override.yml"
DB_DATA_DIR="docker/database/mysql"
API_IMAGE="fleetbase/fleetbase-api:latest"
API_IMAGE_LABEL="io.fleetbase.local-build"

ACTION="start"
case "${1:-}" in
  "")          ;;
  --rebuild)   ACTION="rebuild" ;;
  --stop)      ACTION="stop" ;;
  --reset)     ACTION="reset" ;;
  -h|--help)   sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)           error "Unknown option: $1 (see --help)"; exit 1 ;;
esac

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

###############################################################################
# Docker
###############################################################################
section "Docker"

if ! command -v docker >/dev/null 2>&1; then
  error "Docker is not installed."
  if [[ "$(uname -s)" == "Darwin" ]]; then
    error "Install Docker Desktop (https://www.docker.com/products/docker-desktop/) or OrbStack (https://orbstack.dev),"
    error "e.g. with Homebrew:  brew install --cask orbstack   or   brew install --cask docker"
  else
    error "Install it with:  curl -fsSL https://get.docker.com | sh"
  fi
  exit 1
fi

# Start Docker Desktop / OrbStack on macOS if it isn't running yet.
if ! docker info >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ -d /Applications/OrbStack.app ]]; then
      info "Starting OrbStack..."
      open -a OrbStack
    elif [[ -d /Applications/Docker.app ]]; then
      info "Starting Docker Desktop..."
      open -a Docker
    fi
  fi
  SECONDS=0
  until docker info >/dev/null 2>&1; do
    if (( SECONDS >= 180 )); then
      error "Docker isn't running. Start Docker Desktop (or OrbStack, or the docker service) and retry."
      exit 1
    fi
    sleep 3
  done
fi
success "Docker is running"

if ! docker compose version >/dev/null 2>&1; then
  error "'docker compose' (v2) is required. Update Docker Desktop, or install the Compose plugin."
  exit 1
fi
success "Docker Compose v2 found"

###############################################################################
# Stop / reset / rebuild
###############################################################################
if [[ "$ACTION" == "stop" ]]; then
  docker compose stop
  success "Fleetbase stopped. Your data is kept; start it again with: bash scripts/local-start.sh"
  exit 0
fi

if [[ "$ACTION" == "reset" ]]; then
  warn "This deletes the local Fleetbase install: containers, the database in ${DB_DATA_DIR} and ${OVERRIDE_FILE}."
  read -rp "Type 'yes' to continue: " CONFIRM
  [[ "$CONFIRM" == "yes" ]] || { info "Cancelled."; exit 0; }
  docker compose down --remove-orphans
  # MySQL's files can belong to the container's user, so delete them from a container too.
  if [[ -d "$DB_DATA_DIR" ]]; then
    docker run --rm -v "$PWD/docker/database:/data" alpine:3 rm -rf /data/mysql
  fi
  [[ -f "$OVERRIDE_FILE" ]] && mv "$OVERRIDE_FILE" "${OVERRIDE_FILE}.reset-$(date +%Y%m%d%H%M%S)"
  success "Reset done. Run bash scripts/local-start.sh to install again."
  exit 0
fi

###############################################################################
# Pre-flight
###############################################################################
section "Pre-flight Checks"

MEMORY_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
MEMORY_GB=$(( MEMORY_BYTES / 1024 / 1024 / 1024 ))
if (( MEMORY_BYTES > 0 && MEMORY_BYTES < (MIN_MEMORY_GB * 1024 * 1024 * 1024 * 9 / 10) )); then
  error "Docker has only about ${MEMORY_GB} GB of memory; Fleetbase needs at least ${MIN_MEMORY_GB} GB."
  error "Docker Desktop: Settings → Resources → Memory. OrbStack: Settings → System → Memory limit."
  exit 1
elif (( MEMORY_BYTES > 0 && MEMORY_GB < RECOMMENDED_MEMORY_GB )); then
  warn "Docker has about ${MEMORY_GB} GB of memory. It works, but ${RECOMMENDED_MEMORY_GB} GB+ makes the first build much faster."
else
  success "Docker memory: ${MEMORY_GB} GB"
fi

FREE_GB=$(( $(df -Pk . | awk 'NR==2 {print $4}') / 1024 / 1024 ))
if (( FREE_GB < 15 )); then
  warn "Only ${FREE_GB} GB of disk left here; the images and build need about 15 GB."
else
  success "Free disk: ${FREE_GB} GB"
fi

if [[ "$(uname -m)" == "arm64" || "$(uname -m)" == "aarch64" ]]; then
  info "ARM processor: the websocket image only exists for x86 and runs under emulation."
  info "In Docker Desktop, turn on Settings → General → 'Use Rosetta for x86/amd64 emulation' for speed."
fi

# Ports only matter when Fleetbase's own containers aren't the ones holding them.
if [[ -z "$(docker compose ps -q 2>/dev/null)" ]] && command -v lsof >/dev/null 2>&1; then
  for port_label in "4200:Console" "8000:API" "3306:MySQL" "38000:Websockets"; do
    port="${port_label%%:*}"
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      error "Port ${port} (${port_label##*:}) is already in use by another program:"
      lsof -nP -iTCP:"$port" -sTCP:LISTEN | sed 's/^/     /' >&2
      error "Stop it (a local MySQL is the usual suspect for 3306) and retry."
      exit 1
    fi
  done
  success "Ports 4200, 8000, 3306 and 38000 are free"
fi

###############################################################################
# Install or start
###############################################################################
# The database directory appears once MySQL first starts. Until then nothing depends on the
# credentials in the override, so an install that stopped early (a failed image build, say)
# is simply run again. A directory we can't read belongs to MySQL, so it counts as data.
has_database() {
  [[ -d "$DB_DATA_DIR" ]] && { [[ ! -r "$DB_DATA_DIR" ]] || [[ -n "$(ls -A "$DB_DATA_DIR" 2>/dev/null)" ]]; }
}

# The published image carries every upstream extension (Storefront included) whatever
# api/composer.json says; an image built here is labelled so it can be told apart.
api_image_is_local() {
  [[ "$(docker image inspect -f '{{ index .Config.Labels "io.fleetbase.local-build" }}' "$API_IMAGE" 2>/dev/null)" == "true" ]]
}

build_api_image() {
  section "Building the API"
  info "Building ${API_IMAGE} from this repository. Composer installs the PHP packages, so this takes several minutes."
  local args=(--file docker/Dockerfile --target app-release --tag "$API_IMAGE" --label "${API_IMAGE_LABEL}=true")
  [[ -n "${GITHUB_AUTH_KEY:-}" ]] && args+=(--build-arg "GITHUB_AUTH_KEY=${GITHUB_AUTH_KEY}")
  docker build "${args[@]}" .
  success "API image built"
}

if ! has_database; then
  api_image_is_local || build_api_image
  if [[ -f "$OVERRIDE_FILE" ]]; then
    section "Resuming the Install"
    info "A previous install stopped before the database was created; running it again."
  else
    section "First Run: Installing Fleetbase"
  fi
  info "Downloading images and building the console takes 15-30 minutes the first time."
  FLEETBASE_HOST=localhost bash scripts/docker-install.sh --non-interactive
elif [[ ! -f "$OVERRIDE_FILE" ]]; then
  error "Found a database in ${DB_DATA_DIR} but no ${OVERRIDE_FILE} with its credentials."
  error "Run bash scripts/local-start.sh --reset to start over."
  exit 1
elif [[ "$ACTION" == "rebuild" ]]; then
  build_api_image
  section "Rebuilding"
  info "Rebuilding the console and restarting the stack. This takes several minutes."
  docker compose up -d --build
  docker compose exec -T application bash -c "./deploy.sh"
else
  section "Starting Fleetbase"
  if ! api_image_is_local; then
    warn "The API is running the image published on Docker Hub, which includes extensions this repository removed (Storefront)."
    warn "Build it from this repository with: bash scripts/local-start.sh --rebuild"
  fi
  docker compose up -d
fi

###############################################################################
# Wait until it answers
###############################################################################
section "Waiting for Fleetbase"
SECONDS=0
until curl -fsS --max-time 5 -o /dev/null "$CONSOLE_URL" && \
      [[ "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "$API_URL")" != "000" ]]; do
  if (( SECONDS >= WAIT_MINUTES * 60 )); then
    error "Fleetbase didn't answer within ${WAIT_MINUTES} minutes. See what the containers say:"
    error "  docker compose ps"
    error "  docker compose logs --tail=100 console application"
    exit 1
  fi
  sleep 5
done
success "Console and API are up"

echo
printf '%0.s═' {1..60}; echo
echo -e "  ${BOLD}🏁  Fleetbase is running${RESET}"
printf '%0.s═' {1..60}; echo
echo
echo "  📍  Console → ${CONSOLE_URL}"
echo "      API     → ${API_URL}"
echo
echo "  First time? Create your organization and admin account in the console."
echo "  Change the language from the globe icon in the header (English, Russian, Uzbek)."
echo
echo "  Stop:     bash scripts/local-start.sh --stop"
echo "  Update:   git pull && bash scripts/local-start.sh --rebuild"
echo "  Logs:     docker compose logs -f application"
echo "  Wipe:     bash scripts/local-start.sh --reset"
printf '%0.s═' {1..60}; echo
echo

if [[ "$(uname -s)" == "Darwin" ]]; then
  open "$CONSOLE_URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$CONSOLE_URL" >/dev/null 2>&1 || true
fi
