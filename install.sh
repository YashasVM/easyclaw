#!/usr/bin/env bash
# ==============================================================================
#  ______                  _____ _
# |  ____|                / ____| |
# | |__   __ _ ___ _   _| |    | | __ ___      __
# |  __| / _` / __| | | | |    | |/ _` \ \ /\ / /
# | |___| (_| \__ \ |_| | |____| | (_| |\ V  V /
# |______\__,_|___/\__, |\_____|_|\__,_| \_/\_/
#                   __/ |
#                  |___/
#
#  EasyClaw — the friendliest way to install OpenClaw 🦞
#  https://github.com/openclaw/openclaw
# ==============================================================================
# Version: 1.0.0
# Author:  EasyClaw Installer
# License: MIT
#
# USAGE:
#   curl -fsSL https://raw.githubusercontent.com/YashasVM/easyclaw/main/install.sh | bash
#   -- or --
#   bash install.sh
# ==============================================================================

set -euo pipefail

# ==============================================================================
# GLOBALS
# ==============================================================================
EASYCLAW_VERSION="1.0.0"
OPENCLAW_MIN_NODE="22"            # minimum Node major version
OPENCLAW_REC_NODE="24"            # recommended Node major version
OPENCLAW_DASHBOARD_PORT="18789"
OPENCLAW_CONFIG_DIR="${HOME}/.openclaw"
OPENCLAW_CONFIG_FILE="${OPENCLAW_CONFIG_DIR}/openclaw.json"
INSTALL_LOG="/tmp/easyclaw-install.log"
NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
EASYCLAW_BIN=""                   # set during CLI install step
INSTALL_MODE=""                   # bare-metal | docker | full-server
PROVIDER=""                       # anthropic | openai | google | openrouter
API_KEY=""
ASSISTANT_NAME="Claw"
MODEL=""
DOMAIN=""
declare -a CHANNELS=()

# Redirect ALL output (stdout + stderr) to the log file too
exec > >(tee -a "${INSTALL_LOG}") 2>&1

# ==============================================================================
# COLORS & UI UTILITIES
# ==============================================================================
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  MAGENTA='\033[0;35m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' DIM='' RESET=''
fi

# info <message> — informational blue line
info() {
  printf "${BLUE}${BOLD}[INFO]${RESET}  %s\n" "$*"
}

# success <message> — green checkmark
success() {
  printf "${GREEN}${BOLD}[✓]${RESET}     %s\n" "$*"
}

# warn <message> — yellow warning
warn() {
  printf "${YELLOW}${BOLD}[!]${RESET}     %s\n" "$*"
}

# error <message> — red cross (does NOT exit by itself)
error() {
  printf "${RED}${BOLD}[✗]${RESET}     %s\n" "$*" >&2
}

# step <n> <total> <message> — bold cyan step header
STEP_NUM=0
TOTAL_STEPS=8
step() {
  local n="$1" total="$2"; shift 2
  printf "\n${CYAN}${BOLD}[Step ${n}/${total}]${RESET} ${BOLD}%s${RESET}\n" "$*"
  printf "${DIM}%s${RESET}\n" "$(printf '─%.0s' {1..60})"
}

# ask <prompt> <default> — prompts user, returns answer (or default on Enter)
ask() {
  local prompt="$1" default="${2:-}"
  local response
  if [[ -n "$default" ]]; then
    printf "${CYAN}${BOLD}  ?${RESET} %s ${DIM}[%s]${RESET} " "$prompt" "$default"
  else
    printf "${CYAN}${BOLD}  ?${RESET} %s " "$prompt"
  fi
  read -r response
  echo "${response:-$default}"
}

# ask_secret <prompt> — masked input (no echo)
ask_secret() {
  local prompt="$1"
  local response
  printf "${CYAN}${BOLD}  ?${RESET} %s " "$prompt"
  read -rs response
  echo ""  # newline after hidden input
  echo "$response"
}

# ask_yesno <prompt> <default:y|n> — returns 0 for yes, 1 for no
ask_yesno() {
  local prompt="$1" default="${2:-y}"
  local hint response
  if [[ "$default" == "y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  printf "${CYAN}${BOLD}  ?${RESET} %s %s " "$prompt" "${DIM}${hint}${RESET}"
  read -r response
  response="${response:-$default}"
  case "${response,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# ask_choice <prompt> <options...> — numbered menu, returns chosen index (1-based)
ask_choice() {
  local prompt="$1"; shift
  local options=("$@")
  printf "\n${BOLD}  %s${RESET}\n" "$prompt"
  for i in "${!options[@]}"; do
    printf "  ${CYAN}%d${RESET}) %s\n" "$((i+1))" "${options[$i]}"
  done
  local choice
  while true; do
    printf "${CYAN}${BOLD}  →${RESET} Enter number: "
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      echo "$choice"
      return
    fi
    warn "Please enter a number between 1 and ${#options[@]}"
  done
}

# spinner <pid> <message> — shows a spinner next to <message> until <pid> exits
spinner() {
  local pid="$1" msg="$2"
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  ${CYAN}%s${RESET}  %s" "${frames[$((i % ${#frames[@]}))]}" "$msg"
    sleep 0.08
    i=$((i+1))
  done
  printf "\r  ${GREEN}✓${RESET}  %-60s\n" "$msg"
}

# run_quiet <message> <cmd...> — runs command silently, shows spinner
run_quiet() {
  local msg="$1"; shift
  ("$@" >> "${INSTALL_LOG}" 2>&1) &
  local pid=$!
  spinner "$pid" "$msg"
  wait "$pid" || {
    error "Command failed: $*"
    error "Check the log: ${INSTALL_LOG}"
    return 1
  }
}

# box_top / box_row / box_bottom — draw a pretty box
box_top()    { printf "${CYAN}╔%s╗${RESET}\n" "$(printf '═%.0s' $(seq 1 $1))"; }
box_bottom() { printf "${CYAN}╚%s╝${RESET}\n" "$(printf '═%.0s' $(seq 1 $1))"; }
box_divider(){ printf "${CYAN}╠%s╣${RESET}\n" "$(printf '═%.0s' $(seq 1 $1))"; }
box_row()    {
  local width="$1" content="$2"
  # Strip ANSI escape codes for length calculation
  local plain
  plain="$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')"
  local padded=$(( width - ${#plain} ))
  printf "${CYAN}║${RESET}%s%s${CYAN}║${RESET}\n" "$content" "$(printf ' %.0s' $(seq 1 $padded))"
}

# ==============================================================================
# ERROR HANDLING
# ==============================================================================
INSTALL_ABORTED=false

cleanup() {
  if [[ "$INSTALL_ABORTED" == "true" ]]; then
    printf "\n\n${RED}${BOLD}Installation cancelled.${RESET}\n"
    printf "${DIM}Nothing permanent was changed.${RESET}\n\n"
  fi
}

on_error() {
  local exit_code=$? line_no=${BASH_LINENO[0]}
  INSTALL_ABORTED=true
  printf "\n\n${RED}${BOLD}╔══════════════════════════════════════════╗${RESET}\n"
  printf "${RED}${BOLD}║         Something went wrong  ✗          ║${RESET}\n"
  printf "${RED}${BOLD}╚══════════════════════════════════════════╝${RESET}\n\n"
  error "Exit code ${exit_code} at line ${line_no}"
  printf "\n${YELLOW}What to do:${RESET}\n"
  printf "  1. Read the full log: ${BOLD}${INSTALL_LOG}${RESET}\n"
  printf "  2. Share that file when asking for help.\n"
  printf "  3. Try running the step manually.\n\n"
  printf "${DIM}Log saved to: %s${RESET}\n\n" "${INSTALL_LOG}"
}

trap 'on_error' ERR
trap 'cleanup' EXIT
trap 'INSTALL_ABORTED=true; printf "\n\n${YELLOW}Installation cancelled by user.${RESET}\n\n"; exit 130' INT TERM

# ==============================================================================
# BANNER
# ==============================================================================
print_banner() {
  printf "\n"
  printf "${CYAN}${BOLD}"
  cat << 'BANNER'
  ___                  ___ _
 | __|__ _ ____  _  __|  _| |__ ___ __ __
 | _|/ _` (_-< || |/ _|| |/ _/ _ \ V  V /
 |___\__,_/__/\_, |\__||_|\__\___/\_/\_/
              |__/
BANNER
  printf "${RESET}"
  printf "  ${DIM}The friendliest way to install OpenClaw 🦞${RESET}\n"
  printf "  ${DIM}v%s${RESET}\n\n" "${EASYCLAW_VERSION}"
  printf "  ${DIM}Install log: %s${RESET}\n\n" "${INSTALL_LOG}"
}

# ==============================================================================
# STEP 1: ENVIRONMENT DETECTION
# ==============================================================================
detect_environment() {
  step 1 "${TOTAL_STEPS}" "Checking your system"

  # --- OS Detection ---
  OS_TYPE="unknown"
  OS_PRETTY="Unknown OS"
  IS_WSL=false
  IS_SERVER=false    # heuristic: no DISPLAY and not macOS

  if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL=true
    OS_TYPE="wsl"
    OS_PRETTY="Windows (WSL2)"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    OS_TYPE="macos"
    OS_PRETTY="macOS $(sw_vers -productVersion 2>/dev/null || echo '')"
  elif [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    case "${ID:-}" in
      ubuntu|debian|linuxmint|pop|elementary)
        OS_TYPE="debian"
        OS_PRETTY="${PRETTY_NAME:-Debian/Ubuntu}"
        ;;
      fedora|rhel|centos|rocky|almalinux)
        OS_TYPE="fedora"
        OS_PRETTY="${PRETTY_NAME:-Fedora/RHEL}"
        ;;
      arch|manjaro|endeavouros)
        OS_TYPE="arch"
        OS_PRETTY="${PRETTY_NAME:-Arch Linux}"
        ;;
      *)
        OS_TYPE="linux"
        OS_PRETTY="${PRETTY_NAME:-Linux}"
        ;;
    esac
  fi

  # Heuristic: if there is no DISPLAY, WAYLAND_DISPLAY, or it's a known desktop
  if [[ "$OS_TYPE" != "macos" ]] && [[ -z "${DISPLAY:-}" ]] && [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    IS_SERVER=true
  fi

  # --- Architecture ---
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  ARCH_PRETTY="x86_64 (Intel/AMD)" ;;
    aarch64|arm64) ARCH_PRETTY="arm64 (Apple Silicon / ARM)" ;;
    *)       ARCH_PRETTY="$ARCH" ;;
  esac

  # --- Root check ---
  IS_ROOT=false
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    IS_ROOT=true
  fi

  # --- RAM (MB) ---
  RAM_MB=0
  if [[ "$OS_TYPE" == "macos" ]]; then
    RAM_MB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 ))
  elif [[ -f /proc/meminfo ]]; then
    RAM_MB=$(awk '/MemTotal/ { printf "%d", $2/1024 }' /proc/meminfo)
  fi
  RAM_GB="$(awk "BEGIN { printf \"%.1f\", ${RAM_MB}/1024 }")"

  # --- Disk space (GB free on /) ---
  DISK_FREE_GB=0
  if command -v df &>/dev/null; then
    DISK_FREE_GB=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 0)
  fi

  # --- Node.js ---
  NODE_VERSION="none"
  NODE_MAJOR=0
  NODE_OK=false
  if command -v node &>/dev/null; then
    NODE_VERSION="$(node --version 2>/dev/null | sed 's/v//')"
    NODE_MAJOR="$(echo "$NODE_VERSION" | cut -d. -f1)"
    if (( NODE_MAJOR >= OPENCLAW_MIN_NODE )); then
      NODE_OK=true
    fi
  fi

  # --- Docker ---
  DOCKER_INSTALLED=false
  DOCKER_RUNNING=false
  DOCKER_COMPOSE_AVAILABLE=false
  if command -v docker &>/dev/null; then
    DOCKER_INSTALLED=true
    if docker info &>/dev/null 2>&1; then
      DOCKER_RUNNING=true
    fi
    if docker compose version &>/dev/null 2>&1 || command -v docker-compose &>/dev/null; then
      DOCKER_COMPOSE_AVAILABLE=true
    fi
  fi

  # --- Existing OpenClaw installation ---
  OPENCLAW_INSTALLED=false
  OPENCLAW_INSTALLED_VERSION="none"
  if command -v openclaw &>/dev/null; then
    OPENCLAW_INSTALLED=true
    OPENCLAW_INSTALLED_VERSION="$(openclaw --version 2>/dev/null | head -1 || echo 'unknown')"
  fi

  # --- Print summary box ---
  print_env_summary
}

print_env_summary() {
  local W=50
  printf "\n"
  box_top $W

  # Title row
  local title="  System Summary"
  box_row $W "${BOLD}${title}${RESET}"
  box_divider $W

  # OS
  local os_str="  OS:          ${OS_PRETTY}"
  [[ "$IS_WSL" == "true" ]] && os_str+=" ${YELLOW}(WSL2)${RESET}"
  box_row $W "$os_str"

  # Arch
  box_row $W "  Arch:        ${ARCH_PRETTY}"

  # RAM
  local ram_str="  RAM:         ${RAM_GB} GB"
  if (( RAM_MB > 0 && RAM_MB < 2048 )); then
    ram_str+="  ${YELLOW}⚠ Low (< 2 GB)${RESET}"
  fi
  box_row $W "$ram_str"

  # Disk
  local disk_str="  Disk free:   ${DISK_FREE_GB} GB"
  if (( DISK_FREE_GB > 0 && DISK_FREE_GB < 5 )); then
    disk_str+="  ${YELLOW}⚠ Low (< 5 GB)${RESET}"
  fi
  box_row $W "$disk_str"

  # Node
  local node_str="  Node.js:     ${NODE_VERSION}"
  if [[ "$NODE_OK" == "true" ]]; then
    node_str+="  ${GREEN}✓${RESET}"
  elif [[ "$NODE_VERSION" != "none" ]]; then
    node_str+="  ${YELLOW}⚠ need ≥${OPENCLAW_MIN_NODE}${RESET}"
  else
    node_str+="  ${DIM}(not found)${RESET}"
  fi
  box_row $W "$node_str"

  # Docker
  local docker_str="  Docker:      "
  if [[ "$DOCKER_RUNNING" == "true" ]]; then
    docker_str+="${GREEN}running ✓${RESET}"
  elif [[ "$DOCKER_INSTALLED" == "true" ]]; then
    docker_str+="${YELLOW}installed (not running)${RESET}"
  else
    docker_str+="${DIM}not installed${RESET}"
  fi
  box_row $W "$docker_str"

  # OpenClaw
  local oc_str="  OpenClaw:    "
  if [[ "$OPENCLAW_INSTALLED" == "true" ]]; then
    oc_str+="${YELLOW}already installed (${OPENCLAW_INSTALLED_VERSION})${RESET}"
  else
    oc_str+="${DIM}not installed${RESET}"
  fi
  box_row $W "$oc_str"

  box_bottom $W
  printf "\n"

  # Warnings
  [[ "$IS_ROOT" == "true" ]] && warn "You are running as root. Non-root is strongly recommended."
  if (( RAM_MB > 0 && RAM_MB < 2048 )); then
    warn "Low RAM detected (${RAM_GB} GB). OpenClaw recommends at least 2 GB."
  fi
  if (( DISK_FREE_GB > 0 && DISK_FREE_GB < 5 )); then
    warn "Low disk space (${DISK_FREE_GB} GB free). OpenClaw recommends at least 5 GB."
  fi
  if [[ "$OPENCLAW_INSTALLED" == "true" ]]; then
    warn "OpenClaw is already installed (${OPENCLAW_INSTALLED_VERSION})."
    if ask_yesno "Do you want to upgrade/reinstall?" "y"; then
      info "Proceeding with upgrade/reinstall."
    else
      success "Nothing to do. Goodbye!"
      exit 0
    fi
  fi
}

# ==============================================================================
# STEP 2: CHOOSE DEPLOYMENT MODE
# ==============================================================================
choose_deployment_mode() {
  step 2 "${TOTAL_STEPS}" "Choose your deployment mode"

  # Auto-recommend based on environment
  local recommended=""
  if [[ "$OS_TYPE" == "macos" ]] || [[ "$IS_WSL" == "true" ]]; then
    recommended="bare-metal"
  elif [[ "$IS_SERVER" == "true" ]]; then
    recommended="docker"
  else
    recommended="bare-metal"
  fi

  # Build option labels with recommendation callout
  local opt1="Quick Install    — Direct npm install. Best for personal machines."
  local opt2="Docker Install   — Containerized. Best for servers / VPS."
  local opt3="Full Server Setup — Docker + Caddy + HTTPS + systemd. Best for 24/7 public hosting."

  if [[ "$recommended" == "bare-metal" ]]; then
    opt1="${opt1} ${GREEN}← Recommended for you${RESET}"
  elif [[ "$recommended" == "docker" ]]; then
    opt2="${opt2} ${GREEN}← Recommended for you${RESET}"
  fi

  printf "\n${DIM}EasyClaw detected: %s%s${RESET}\n" \
    "$OS_PRETTY" \
    "$([[ "$IS_SERVER" == "true" ]] && echo " (server/headless)" || echo "")"
  printf "\n"

  local choice
  choice="$(ask_choice "How do you want to run OpenClaw?" \
    "$opt1" \
    "$opt2" \
    "$opt3")"

  case "$choice" in
    1) INSTALL_MODE="bare-metal"   ; success "Mode: Quick Install (bare-metal)" ;;
    2) INSTALL_MODE="docker"       ; success "Mode: Docker Install" ;;
    3) INSTALL_MODE="full-server"  ; success "Mode: Full Server Setup" ;;
  esac
}

# ==============================================================================
# STEP 3: INSTALL DEPENDENCIES
# ==============================================================================
install_dependencies() {
  step 3 "${TOTAL_STEPS}" "Installing dependencies"

  case "$INSTALL_MODE" in
    bare-metal)
      install_deps_bare_metal
      ;;
    docker|full-server)
      install_deps_docker
      if [[ "$INSTALL_MODE" == "full-server" ]]; then
        install_deps_caddy
      fi
      ;;
  esac
}

# ---- Helpers for system packages ----
pkg_install() {
  # pkg_install <package...>
  info "Installing packages: $*"
  case "$OS_TYPE" in
    macos)
      if ! command -v brew &>/dev/null; then
        info "Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      fi
      run_quiet "Installing $*" brew install "$@"
      ;;
    debian)
      run_quiet "Updating package lists" sudo apt-get update -qq
      run_quiet "Installing $*" sudo apt-get install -y "$@"
      ;;
    fedora)
      run_quiet "Installing $*" sudo dnf install -y "$@"
      ;;
    arch)
      run_quiet "Installing $*" sudo pacman -Sy --noconfirm "$@"
      ;;
    wsl|linux)
      run_quiet "Updating package lists" sudo apt-get update -qq
      run_quiet "Installing $*" sudo apt-get install -y "$@"
      ;;
    *)
      warn "Unknown OS — please install manually: $*"
      ;;
  esac
}

pkg_missing() {
  # Returns 0 if command is missing, 1 if found
  ! command -v "$1" &>/dev/null
}

install_deps_bare_metal() {
  # Install git, curl, jq if missing
  for tool in git curl jq; do
    if pkg_missing "$tool"; then
      pkg_install "$tool"
    else
      success "$tool already installed"
    fi
  done

  # Node.js via nvm
  if [[ "$NODE_OK" == "false" ]]; then
    info "Node.js ${OPENCLAW_REC_NODE} is required. Installing via nvm..."
    install_node_via_nvm
  else
    success "Node.js ${NODE_VERSION} is ready (≥ ${OPENCLAW_MIN_NODE})"
  fi
}

install_node_via_nvm() {
  # Install nvm if not present
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    info "Installing nvm (Node Version Manager)..."
    run_quiet "Downloading nvm" \
      bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/HEAD/install.sh | bash'
  else
    success "nvm already installed at ${NVM_DIR}"
  fi

  # Source nvm for this session
  export NVM_DIR
  # shellcheck source=/dev/null
  [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

  # Install & activate Node 24
  info "Installing Node.js ${OPENCLAW_REC_NODE} (this may take a minute)..."
  nvm install "${OPENCLAW_REC_NODE}" >> "${INSTALL_LOG}" 2>&1
  nvm use "${OPENCLAW_REC_NODE}"     >> "${INSTALL_LOG}" 2>&1
  nvm alias default "${OPENCLAW_REC_NODE}" >> "${INSTALL_LOG}" 2>&1

  # Add nvm to shell profile so it persists
  local profile_file
  if [[ -f "${HOME}/.zshrc" ]]; then
    profile_file="${HOME}/.zshrc"
  elif [[ -f "${HOME}/.bashrc" ]]; then
    profile_file="${HOME}/.bashrc"
  else
    profile_file="${HOME}/.profile"
  fi

  if ! grep -q 'NVM_DIR' "${profile_file}" 2>/dev/null; then
    {
      echo ''
      echo '# Added by EasyClaw installer'
      echo 'export NVM_DIR="$HOME/.nvm"'
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
      echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    } >> "${profile_file}"
    info "nvm sourced in ${profile_file}"
  fi

  success "Node.js $(node --version) installed via nvm"
}

install_deps_docker() {
  if [[ "$DOCKER_RUNNING" == "true" ]]; then
    success "Docker is already running"
    return
  fi

  if [[ "$DOCKER_INSTALLED" == "true" ]]; then
    warn "Docker is installed but not running."
    info "Attempting to start Docker..."
    if command -v systemctl &>/dev/null; then
      sudo systemctl start docker
      sleep 3
    fi
    if docker info &>/dev/null 2>&1; then
      DOCKER_RUNNING=true
      success "Docker started"
      return
    fi
    error "Could not start Docker automatically. Please start Docker and re-run this script."
    exit 1
  fi

  info "Docker not found. Installing Docker Engine..."
  if [[ "$OS_TYPE" == "macos" ]]; then
    warn "On macOS, please install Docker Desktop manually:"
    warn "  https://docs.docker.com/desktop/mac/install/"
    warn "Then re-run this installer."
    exit 1
  fi

  # Linux — use official Docker install script
  run_quiet "Downloading Docker install script" \
    bash -c 'curl -fsSL https://get.docker.com -o /tmp/get-docker.sh'
  run_quiet "Installing Docker Engine" \
    bash /tmp/get-docker.sh

  # Add current user to docker group (so sudo isn't needed)
  if ! groups | grep -qw docker; then
    info "Adding ${USER} to the docker group..."
    sudo usermod -aG docker "${USER}" >> "${INSTALL_LOG}" 2>&1 || true
    warn "You may need to log out and back in for group changes to take effect."
    warn "For this install, we'll use sudo docker where needed."
    DOCKER_SUDO="sudo"
  else
    DOCKER_SUDO=""
  fi

  # Start & enable Docker
  if command -v systemctl &>/dev/null; then
    run_quiet "Enabling Docker service" sudo systemctl enable docker
    run_quiet "Starting Docker service"  sudo systemctl start  docker
  fi

  DOCKER_INSTALLED=true
  DOCKER_RUNNING=true
  success "Docker Engine installed and running"

  # Verify Compose
  if ! docker compose version &>/dev/null 2>&1; then
    warn "docker-compose-plugin not found, installing..."
    pkg_install docker-compose-plugin
  fi
  DOCKER_COMPOSE_AVAILABLE=true
  success "Docker Compose ready"
}

install_deps_caddy() {
  if command -v caddy &>/dev/null; then
    success "Caddy already installed ($(caddy version 2>/dev/null | head -1))"
    return
  fi
  info "Installing Caddy web server..."
  case "$OS_TYPE" in
    debian|wsl|linux)
      run_quiet "Adding Caddy apt repo" bash -c '
        sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
        curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" | \
          sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf "https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt" | \
          sudo tee /etc/apt/sources.list.d/caddy-stable.list
        sudo apt-get update -qq
        sudo apt-get install -y caddy
      '
      ;;
    fedora)
      run_quiet "Installing Caddy" bash -c "sudo dnf install -y 'dnf-command(copr)' && sudo dnf copr enable @caddy/caddy -y && sudo dnf install -y caddy"
      ;;
    macos)
      run_quiet "Installing Caddy via Homebrew" brew install caddy
      ;;
    *)
      warn "Cannot install Caddy automatically on ${OS_PRETTY}."
      warn "Please install it manually: https://caddyserver.com/docs/install"
      if ! ask_yesno "Continue anyway?" "n"; then exit 1; fi
      ;;
  esac
  success "Caddy installed"
}

# ==============================================================================
# STEP 4: CONFIGURE OPENCLAW (Interactive)
# ==============================================================================
configure_openclaw() {
  step 4 "${TOTAL_STEPS}" "Configuring your AI assistant"
  printf "\n${DIM}Just a few quick questions — press Enter to accept the defaults.${RESET}\n\n"

  # --- 4.1 Assistant name ---
  printf "${DIM}  This is the name your assistant responds to.${RESET}\n"
  ASSISTANT_NAME="$(ask "What should we call your AI assistant?" "Claw")"

  # --- 4.2 AI Provider ---
  printf "\n${DIM}  EasyClaw supports all major AI providers.${RESET}\n"
  local provider_choice
  provider_choice="$(ask_choice "Which AI provider do you want to use?" \
    "Anthropic (Claude)   — Recommended, best quality" \
    "OpenAI (GPT)         — Popular, powerful" \
    "Google (Gemini)      — Free tier available" \
    "OpenRouter           — Access 100+ models with one key")"

  local provider_url=""
  case "$provider_choice" in
    1)
      PROVIDER="anthropic"
      MODEL="anthropic/claude-opus-4-5"
      provider_url="https://console.anthropic.com/settings/keys"
      ;;
    2)
      PROVIDER="openai"
      MODEL="openai/gpt-4o"
      provider_url="https://platform.openai.com/api-keys"
      ;;
    3)
      PROVIDER="google"
      MODEL="google/gemini-2.0-flash"
      provider_url="https://aistudio.google.com/app/apikey"
      ;;
    4)
      PROVIDER="openrouter"
      MODEL="openrouter/anthropic/claude-opus-4-5"
      provider_url="https://openrouter.ai/keys"
      ;;
  esac
  success "Provider: ${PROVIDER} (model: ${MODEL})"

  # --- 4.3 API Key (hidden) ---
  printf "\n${DIM}  Get your API key from: ${CYAN}%s${RESET}\n\n" "$provider_url"
  local key_valid=false
  while [[ "$key_valid" == "false" ]]; do
    API_KEY="$(ask_secret "Paste your API key (input is hidden):")"
    if [[ ${#API_KEY} -lt 8 ]]; then
      warn "That key looks too short — are you sure it's correct?"
      if ask_yesno "Try again?" "y"; then
        continue
      fi
    fi
    key_valid=true
  done
  success "API key received (${#API_KEY} characters)"

  # --- 4.4 Messaging channels ---
  printf "\n${DIM}  You can always add more channels later with: ${CYAN}easyclaw channels add${RESET}\n\n"
  printf "${BOLD}  Which messaging channels do you want to connect?${RESET}\n"
  printf "${DIM}  Space to toggle, Enter when done.${RESET}\n\n"

  local channel_options=("None — use web dashboard only" "Telegram" "Discord" "WhatsApp" "Slack")
  local selected=()

  # Simple numbered multi-select implementation
  printf "  ${DIM}Enter the numbers you want (comma-separated), e.g: 2,3${RESET}\n"
  for i in "${!channel_options[@]}"; do
    printf "  ${CYAN}%d${RESET}) %s\n" "$((i+1))" "${channel_options[$i]}"
  done
  printf "${CYAN}${BOLD}  →${RESET} Your choices (default: 1 — web only): "
  read -r channel_input
  channel_input="${channel_input:-1}"

  # Parse comma-separated choices
  IFS=',' read -ra picks <<< "$channel_input"
  for pick in "${picks[@]}"; do
    pick="$(echo "$pick" | tr -d ' ')"
    case "$pick" in
      1) ;; # none / dashboard only
      2) CHANNELS+=("telegram") ;;
      3) CHANNELS+=("discord") ;;
      4) CHANNELS+=("whatsapp") ;;
      5) CHANNELS+=("slack") ;;
    esac
  done

  if [[ ${#CHANNELS[@]} -eq 0 ]]; then
    success "No channels selected — web dashboard only"
  else
    success "Channels selected: ${CHANNELS[*]}"
  fi

  # --- 4.5 Channel-specific tokens ---
  configure_channel_tokens

  # --- 4.6 Domain (full-server only) ---
  if [[ "$INSTALL_MODE" == "full-server" ]]; then
    printf "\n${DIM}  For HTTPS to work, you need a domain pointed at this server's IP.${RESET}\n"
    DOMAIN="$(ask "What is your domain name?" "openclaw.example.com")"
    success "Domain: ${DOMAIN}"
  fi
}

configure_channel_tokens() {
  local TELEGRAM_TOKEN=""
  local DISCORD_TOKEN=""
  local SLACK_BOT_TOKEN=""
  local SLACK_APP_TOKEN=""

  for ch in "${CHANNELS[@]}"; do
    case "$ch" in
      telegram)
        printf "\n${CYAN}${BOLD}  Telegram Setup${RESET}\n"
        printf "${DIM}  Create a bot at: https://t.me/BotFather — send /newbot and follow the steps.${RESET}\n\n"
        TELEGRAM_TOKEN="$(ask_secret "Paste your Telegram Bot Token:")"
        success "Telegram token received"
        ;;
      discord)
        printf "\n${CYAN}${BOLD}  Discord Setup${RESET}\n"
        printf "${DIM}  Create a bot at: https://discord.com/developers/applications${RESET}\n"
        printf "${DIM}  → New Application → Bot → Reset Token → copy it here.${RESET}\n\n"
        DISCORD_TOKEN="$(ask_secret "Paste your Discord Bot Token:")"
        success "Discord token received"
        ;;
      whatsapp)
        printf "\n${CYAN}${BOLD}  WhatsApp Setup${RESET}\n"
        printf "${DIM}  No token needed! After install, a QR code will appear — just scan it with WhatsApp.${RESET}\n"
        success "WhatsApp: will show QR code after install"
        ;;
      slack)
        printf "\n${CYAN}${BOLD}  Slack Setup${RESET}\n"
        printf "${DIM}  Create a Slack app at: https://api.slack.com/apps${RESET}\n"
        printf "${DIM}  Bot Token  = xoxb-...  (OAuth & Permissions page)${RESET}\n"
        printf "${DIM}  App Token  = xapp-...  (Basic Information → App-Level Tokens)${RESET}\n\n"
        SLACK_BOT_TOKEN="$(ask_secret "Paste your Slack Bot Token (xoxb-...):")"
        SLACK_APP_TOKEN="$(ask_secret "Paste your Slack App Token (xapp-...):")"
        success "Slack tokens received"
        ;;
    esac
  done

  # Export channel tokens so later steps can use them
  export TELEGRAM_TOKEN DISCORD_TOKEN SLACK_BOT_TOKEN SLACK_APP_TOKEN
}

# ==============================================================================
# STEP 5: INSTALL OPENCLAW
# ==============================================================================
install_openclaw() {
  step 5 "${TOTAL_STEPS}" "Installing OpenClaw"

  case "$INSTALL_MODE" in
    bare-metal)   install_openclaw_bare_metal ;;
    docker)       install_openclaw_docker ;;
    full-server)  install_openclaw_docker; install_openclaw_full_server ;;
  esac
}

install_openclaw_bare_metal() {
  info "Installing OpenClaw via npm..."

  # Re-source nvm in case we just installed it this session
  export NVM_DIR
  [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

  run_quiet "Installing openclaw globally" \
    npm install -g openclaw@latest

  success "openclaw installed: $(openclaw --version 2>/dev/null | head -1 || echo 'ok')"

  # Write config file directly (more reliable than non-interactive flags)
  write_openclaw_config

  info "Running openclaw onboard..."
  openclaw onboard --install-daemon >> "${INSTALL_LOG}" 2>&1 || {
    warn "openclaw onboard had issues — check ${INSTALL_LOG}"
    warn "You may need to run 'openclaw onboard' manually after install."
  }

  success "OpenClaw onboarding complete"
}

install_openclaw_docker() {
  local DEPLOY_DIR
  if [[ "${IS_ROOT}" == "true" ]]; then
    DEPLOY_DIR="/opt/easyclaw"
  else
    DEPLOY_DIR="${HOME}/easyclaw"
  fi

  info "Deploying OpenClaw to ${DEPLOY_DIR}..."
  mkdir -p "${DEPLOY_DIR}/openclaw"
  cd "${DEPLOY_DIR}"

  # Clone if needed
  if [[ ! -d "${DEPLOY_DIR}/openclaw/.git" ]]; then
    run_quiet "Cloning OpenClaw repository" \
      git clone --depth=1 https://github.com/openclaw/openclaw.git openclaw
  else
    info "OpenClaw repo already present — pulling latest..."
    (cd openclaw && git pull --ff-only >> "${INSTALL_LOG}" 2>&1) || true
  fi

  # Generate .env
  generate_env_file "${DEPLOY_DIR}/.env"

  # Generate docker-compose.yml
  generate_docker_compose "${DEPLOY_DIR}/docker-compose.yml"

  # Start containers
  run_quiet "Starting OpenClaw containers" \
    docker compose --project-directory "${DEPLOY_DIR}" up -d

  export DEPLOY_DIR
  success "OpenClaw containers started"
}

install_openclaw_full_server() {
  info "Configuring Caddy reverse proxy + systemd..."

  local DEPLOY_DIR="${DEPLOY_DIR:-${HOME}/easyclaw}"

  # Generate Caddyfile
  generate_caddyfile "${DEPLOY_DIR}/Caddyfile"

  # Point Caddy at our file
  sudo mkdir -p /etc/caddy
  sudo cp "${DEPLOY_DIR}/Caddyfile" /etc/caddy/Caddyfile
  sudo systemctl reload caddy 2>/dev/null || sudo systemctl start caddy

  # systemd service for docker-compose
  generate_systemd_service "${DEPLOY_DIR}"
  sudo systemctl daemon-reload
  sudo systemctl enable easyclaw.service
  sudo systemctl start  easyclaw.service

  success "systemd service 'easyclaw' enabled and started"
  success "Caddy reverse proxy configured for ${DOMAIN}"
}

# --- Template Generators ---

generate_env_file() {
  local path="$1"
  info "Writing .env to ${path}..."
  cat > "$path" <<ENVFILE
# EasyClaw — generated by EasyClaw installer v${EASYCLAW_VERSION}
OPENCLAW_ASSISTANT_NAME="${ASSISTANT_NAME}"
OPENCLAW_PROVIDER="${PROVIDER}"
OPENCLAW_MODEL="${MODEL}"
OPENCLAW_API_KEY="${API_KEY}"
OPENCLAW_PORT=${OPENCLAW_DASHBOARD_PORT}

# Channel tokens (empty = channel disabled)
TELEGRAM_BOT_TOKEN="${TELEGRAM_TOKEN:-}"
DISCORD_BOT_TOKEN="${DISCORD_TOKEN:-}"
SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-}"
SLACK_APP_TOKEN="${SLACK_APP_TOKEN:-}"
ENVFILE
  chmod 600 "$path"
  success ".env written"
}

generate_docker_compose() {
  local path="$1"
  info "Generating docker-compose.yml..."
  cat > "$path" <<'COMPOSE'
# Generated by EasyClaw installer
version: "3.9"

services:
  openclaw:
    image: node:24-slim
    working_dir: /app
    volumes:
      - ./openclaw:/app
      - openclaw_data:/root/.openclaw
    env_file:
      - .env
    environment:
      - NODE_ENV=production
    ports:
      - "${OPENCLAW_PORT:-18789}:18789"
    command: >
      bash -c "npm install -g openclaw@latest &&
               openclaw onboard --install-daemon &&
               openclaw gateway --port 18789"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:18789/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

volumes:
  openclaw_data:
COMPOSE
  success "docker-compose.yml written"
}

generate_caddyfile() {
  local path="$1"
  info "Generating Caddyfile for ${DOMAIN}..."
  cat > "$path" <<CADDYFILE
# Generated by EasyClaw installer
${DOMAIN} {
    reverse_proxy localhost:${OPENCLAW_DASHBOARD_PORT}

    # Automatic HTTPS (Caddy handles Let's Encrypt certs)
    encode gzip
    log {
        output file /var/log/caddy/openclaw.log
    }
}
CADDYFILE
  success "Caddyfile written"
}

generate_systemd_service() {
  local deploy_dir="$1"
  info "Creating systemd service..."
  sudo tee /etc/systemd/system/easyclaw.service > /dev/null <<SERVICE
# Generated by EasyClaw installer
[Unit]
Description=EasyClaw / OpenClaw AI Assistant
Documentation=https://github.com/openclaw/openclaw
After=docker.service network-online.target
Wants=docker.service

[Service]
Type=simple
User=${USER}
WorkingDirectory=${deploy_dir}
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE
  success "systemd service file written"
}

write_openclaw_config() {
  info "Writing OpenClaw config to ${OPENCLAW_CONFIG_FILE}..."
  mkdir -p "${OPENCLAW_CONFIG_DIR}"
  chmod 700 "${OPENCLAW_CONFIG_DIR}"

  # Build channels JSON snippet
  local channels_json=""
  for ch in "${CHANNELS[@]}"; do
    case "$ch" in
      telegram)
        channels_json+="\"telegram\": { \"botToken\": \"${TELEGRAM_TOKEN:-}\" },"
        ;;
      discord)
        channels_json+="\"discord\": { \"token\": \"${DISCORD_TOKEN:-}\" },"
        ;;
      slack)
        channels_json+="\"slack\": { \"botToken\": \"${SLACK_BOT_TOKEN:-}\", \"appToken\": \"${SLACK_APP_TOKEN:-}\" },"
        ;;
      whatsapp)
        channels_json+="\"whatsapp\": { \"allowFrom\": [\"*\"] },"
        ;;
    esac
  done
  # Remove trailing comma
  channels_json="${channels_json%,}"

  cat > "${OPENCLAW_CONFIG_FILE}" <<JSONCONF
{
  "agent": {
    "name": "${ASSISTANT_NAME}",
    "model": "${MODEL}",
    "provider": "${PROVIDER}",
    "apiKey": "${API_KEY}"
  },
  "gateway": {
    "port": ${OPENCLAW_DASHBOARD_PORT},
    "auth": {
      "mode": "password"
    }
  },
  "channels": {
    ${channels_json}
  }
}
JSONCONF
  chmod 600 "${OPENCLAW_CONFIG_FILE}"
  success "Config written to ${OPENCLAW_CONFIG_FILE}"
}

# ==============================================================================
# STEP 6: CONFIGURE CHANNELS
# ==============================================================================
configure_channels() {
  step 6 "${TOTAL_STEPS}" "Configuring channels"

  if [[ ${#CHANNELS[@]} -eq 0 ]]; then
    info "No channels to configure — skipping."
    return
  fi

  for ch in "${CHANNELS[@]}"; do
    case "$ch" in
      telegram)
        info "Telegram: token written to config."
        success "Telegram ready"
        ;;
      discord)
        info "Discord: token written to config."
        success "Discord ready"
        ;;
      whatsapp)
        warn "WhatsApp: QR code will appear when OpenClaw starts."
        info "Run: openclaw channels login"
        info "Then scan the QR code with your phone's WhatsApp."
        success "WhatsApp: configured (QR code on first start)"
        ;;
      slack)
        info "Slack: tokens written to config."
        success "Slack ready"
        ;;
    esac
  done
}

# ==============================================================================
# STEP 7: VERIFY & CELEBRATE
# ==============================================================================
verify_and_celebrate() {
  step 7 "${TOTAL_STEPS}" "Verifying installation"

  local all_ok=true

  # Health checks
  case "$INSTALL_MODE" in
    bare-metal)
      if command -v openclaw &>/dev/null; then
        success "openclaw binary found: $(openclaw --version 2>/dev/null | head -1 || echo 'ok')"
      else
        warn "openclaw binary not found in PATH — you may need to restart your shell"
        info "Try: source ~/.bashrc  or  source ~/.zshrc"
        all_ok=false
      fi

      if openclaw doctor &>/dev/null 2>&1; then
        success "openclaw doctor: OK"
      else
        warn "openclaw doctor reported issues — check ${INSTALL_LOG}"
      fi
      ;;

    docker|full-server)
      local DEPLOY_DIR="${DEPLOY_DIR:-${HOME}/easyclaw}"
      sleep 5  # Give containers a moment to start

      if docker compose --project-directory "${DEPLOY_DIR}" ps 2>/dev/null | grep -q "Up"; then
        success "Docker container is running"
      else
        warn "Container may not be running yet — check: docker compose ps"
        all_ok=false
      fi

      # Check if dashboard port is responding
      if curl -sf "http://localhost:${OPENCLAW_DASHBOARD_PORT}/health" &>/dev/null; then
        success "Dashboard responding on port ${OPENCLAW_DASHBOARD_PORT}"
      else
        info "Dashboard not yet responding — it may still be starting up (takes ~30-60s)"
      fi
      ;;
  esac

  # Print the celebration box
  print_summary_box "$all_ok"
}

print_summary_box() {
  local all_ok="${1:-true}"
  local W=50

  local channel_list="None (web only)"
  if [[ ${#CHANNELS[@]} -gt 0 ]]; then
    channel_list="$(IFS=', '; echo "${CHANNELS[*]^}")"
  fi

  local mode_pretty
  case "$INSTALL_MODE" in
    bare-metal)  mode_pretty="Quick Install (bare-metal)" ;;
    docker)      mode_pretty="Docker" ;;
    full-server) mode_pretty="Full Server (Docker + Caddy)" ;;
  esac

  local provider_pretty
  case "$PROVIDER" in
    anthropic)  provider_pretty="Anthropic (Claude)" ;;
    openai)     provider_pretty="OpenAI (GPT)" ;;
    google)     provider_pretty="Google (Gemini)" ;;
    openrouter) provider_pretty="OpenRouter" ;;
  esac

  printf "\n"
  box_top $W

  if [[ "$all_ok" == "true" ]]; then
    box_row $W "  ${GREEN}${BOLD}🦞  EasyClaw Setup Complete!  🦞${RESET}"
  else
    box_row $W "  ${YELLOW}${BOLD}🦞  EasyClaw — Mostly Done!  🦞${RESET}"
  fi

  box_divider $W
  box_row $W ""
  box_row $W "  ${BOLD}Dashboard:${RESET}  http://localhost:${OPENCLAW_DASHBOARD_PORT}"

  if [[ "$INSTALL_MODE" == "full-server" ]] && [[ -n "${DOMAIN:-}" ]]; then
    box_row $W "  ${BOLD}Public URL:${RESET} https://${DOMAIN}"
  fi

  box_row $W "  ${BOLD}Assistant:${RESET}  ${ASSISTANT_NAME}"
  box_row $W "  ${BOLD}Provider:${RESET}   ${provider_pretty}"
  box_row $W "  ${BOLD}Channels:${RESET}   ${channel_list}"
  box_row $W "  ${BOLD}Mode:${RESET}       ${mode_pretty}"
  box_row $W ""
  box_divider $W
  box_row $W "  ${BOLD}Quick commands:${RESET}"
  box_row $W "    ${CYAN}easyclaw status${RESET}   — Check health"
  box_row $W "    ${CYAN}easyclaw update${RESET}   — Update OpenClaw"
  box_row $W "    ${CYAN}easyclaw logs${RESET}     — View logs"
  box_row $W "    ${CYAN}easyclaw backup${RESET}   — Backup config"
  box_row $W ""
  box_bottom $W

  if [[ ${#CHANNELS[@]} -gt 0 ]]; then
    printf "\n${YELLOW}${BOLD}  Next steps:${RESET}\n"
    for ch in "${CHANNELS[@]}"; do
      case "$ch" in
        whatsapp)
          printf "  • ${BOLD}WhatsApp:${RESET} run ${CYAN}openclaw channels login${RESET} to see the QR code\n"
          ;;
        telegram)
          printf "  • ${BOLD}Telegram:${RESET} search for your bot in Telegram and send /start\n"
          ;;
        discord)
          printf "  • ${BOLD}Discord:${RESET} invite your bot using the Developer Portal\n"
          ;;
        slack)
          printf "  • ${BOLD}Slack:${RESET} install your app from https://api.slack.com/apps\n"
          ;;
      esac
    done
  fi

  printf "\n${DIM}Full install log: %s${RESET}\n" "${INSTALL_LOG}"
  printf "\n"
}

# ==============================================================================
# STEP 8: INSTALL EASYCLAW CLI WRAPPER
# ==============================================================================
install_easyclaw_cli() {
  step 8 "${TOTAL_STEPS}" "Installing the EasyClaw CLI"

  # Pick a bin directory
  if [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
    EASYCLAW_BIN="/usr/local/bin/easyclaw"
  elif [[ "$IS_ROOT" == "true" ]]; then
    EASYCLAW_BIN="/usr/local/bin/easyclaw"
  else
    mkdir -p "${HOME}/.local/bin"
    EASYCLAW_BIN="${HOME}/.local/bin/easyclaw"
  fi

  local DEPLOY_DIR="${DEPLOY_DIR:-${HOME}/easyclaw}"

  info "Installing EasyClaw CLI to ${EASYCLAW_BIN}..."

  # Write the CLI wrapper script
  if [[ "$IS_ROOT" == "true" ]] || [[ "$EASYCLAW_BIN" == "/usr/local/bin/easyclaw" ]]; then
    write_cli_wrapper | sudo tee "${EASYCLAW_BIN}" > /dev/null
    sudo chmod +x "${EASYCLAW_BIN}"
  else
    write_cli_wrapper > "${EASYCLAW_BIN}"
    chmod +x "${EASYCLAW_BIN}"
  fi

  # Ensure ~/.local/bin is in PATH
  if [[ "$EASYCLAW_BIN" == "${HOME}/.local/bin/easyclaw" ]]; then
    local profile_file
    if [[ -f "${HOME}/.zshrc" ]]; then
      profile_file="${HOME}/.zshrc"
    else
      profile_file="${HOME}/.bashrc"
    fi
    if ! grep -q '\.local/bin' "${profile_file}" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${profile_file}"
      info "Added ~/.local/bin to PATH in ${profile_file}"
    fi
    export PATH="${HOME}/.local/bin:${PATH}"
  fi

  success "EasyClaw CLI installed at ${EASYCLAW_BIN}"
}

write_cli_wrapper() {
  # The variables below are expanded at write time (single quotes used selectively)
  local deploy_dir="${DEPLOY_DIR:-${HOME}/easyclaw}"
  local install_mode="${INSTALL_MODE}"
  local log_file="${INSTALL_LOG}"

cat <<CLISCRIPT
#!/usr/bin/env bash
# EasyClaw CLI wrapper — installed by EasyClaw installer v${EASYCLAW_VERSION}
# Wraps common OpenClaw management commands.

set -euo pipefail

INSTALL_MODE="${install_mode}"
DEPLOY_DIR="${deploy_dir}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

_oc() {
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    openclaw "\$@"
  else
    docker compose --project-directory "\$DEPLOY_DIR" exec openclaw openclaw "\$@" 2>/dev/null || \
      docker compose --project-directory "\$DEPLOY_DIR" run --rm openclaw openclaw "\$@"
  fi
}

cmd_status() {
  echo -e "\${CYAN}\${BOLD}OpenClaw Status\${RESET}"
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    _oc doctor 2>/dev/null || echo "openclaw not in PATH — try restarting your shell"
    _oc gateway status 2>/dev/null || true
  else
    docker compose --project-directory "\$DEPLOY_DIR" ps
  fi
}

cmd_update() {
  echo -e "\${CYAN}\${BOLD}Updating OpenClaw...\${RESET}"
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    npm install -g openclaw@latest
    _oc update --channel stable
  else
    docker compose --project-directory "\$DEPLOY_DIR" pull
    docker compose --project-directory "\$DEPLOY_DIR" up -d
  fi
  echo -e "\${GREEN}Update complete!\${RESET}"
}

cmd_logs() {
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    _oc gateway --verbose 2>&1 | head -100 || \
      journalctl -u openclaw --no-pager -n 100 2>/dev/null || \
      echo "No daemon logs found. Run 'openclaw gateway --verbose' to see live output."
  else
    docker compose --project-directory "\$DEPLOY_DIR" logs --tail=100 -f
  fi
}

cmd_backup() {
  local ts; ts=\$(date +%Y%m%d_%H%M%S)
  local out="\${HOME}/easyclaw-backup-\${ts}.tar.gz"
  echo -e "\${CYAN}Backing up to \${out}...\${RESET}"
  tar -czf "\$out" \
    "\${HOME}/.openclaw" 2>/dev/null || true
  if [[ "\$INSTALL_MODE" != "bare-metal" ]] && [[ -f "\${DEPLOY_DIR}/.env" ]]; then
    tar -rzf "\$out" "\${DEPLOY_DIR}/.env" 2>/dev/null || true
  fi
  echo -e "\${GREEN}Backup saved to: \${out}\${RESET}"
}

cmd_channels() {
  local sub="\${2:-}"
  case "\$sub" in
    add) _oc channels login ;;
    ls|list) _oc channels list 2>/dev/null || echo "Run: openclaw channels list" ;;
    *) echo "Usage: easyclaw channels [add|list]" ;;
  esac
}

cmd_help() {
  echo -e "\${CYAN}\${BOLD}EasyClaw CLI v${EASYCLAW_VERSION}\${RESET}"
  echo ""
  echo -e "  \${BOLD}easyclaw status\${RESET}           Check OpenClaw health"
  echo -e "  \${BOLD}easyclaw update\${RESET}           Update to latest OpenClaw"
  echo -e "  \${BOLD}easyclaw logs\${RESET}             View live logs"
  echo -e "  \${BOLD}easyclaw backup\${RESET}           Back up config & data"
  echo -e "  \${BOLD}easyclaw channels add\${RESET}     Connect a new channel"
  echo -e "  \${BOLD}easyclaw channels list\${RESET}    List connected channels"
  echo -e "  \${BOLD}easyclaw restart\${RESET}          Restart OpenClaw"
  echo -e "  \${BOLD}easyclaw stop\${RESET}             Stop OpenClaw"
  echo -e "  \${BOLD}easyclaw start\${RESET}            Start OpenClaw"
  echo ""
}

cmd_restart() {
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    _oc restart 2>/dev/null || { killall openclaw 2>/dev/null || true; openclaw gateway &; }
  else
    docker compose --project-directory "\$DEPLOY_DIR" restart
  fi
  echo -e "\${GREEN}Restarted!\${RESET}"
}

cmd_stop() {
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    killall openclaw 2>/dev/null || true
  else
    docker compose --project-directory "\$DEPLOY_DIR" stop
  fi
  echo -e "\${YELLOW}Stopped.\${RESET}"
}

cmd_start() {
  if [[ "\$INSTALL_MODE" == "bare-metal" ]]; then
    openclaw gateway --port 18789 &
    echo -e "\${GREEN}Started! Dashboard: http://localhost:18789\${RESET}"
  else
    docker compose --project-directory "\$DEPLOY_DIR" up -d
    echo -e "\${GREEN}Started! Dashboard: http://localhost:18789\${RESET}"
  fi
}

# ---- Main dispatcher ----
CMD="\${1:-help}"
case "\$CMD" in
  status)   cmd_status ;;
  update)   cmd_update ;;
  logs)     cmd_logs ;;
  backup)   cmd_backup ;;
  channels) cmd_channels "\$@" ;;
  restart)  cmd_restart ;;
  stop)     cmd_stop ;;
  start)    cmd_start ;;
  help|-h|--help) cmd_help ;;
  *)
    echo -e "\${RED}Unknown command: \$CMD\${RESET}"
    cmd_help
    exit 1
    ;;
esac
CLISCRIPT
}

# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================
main() {
  # Clear log file at start of fresh run
  : > "${INSTALL_LOG}"

  print_banner

  printf "${BOLD}Welcome!${RESET} This script will install OpenClaw on your machine.\n"
  printf "It'll ask a few simple questions, then do everything automatically.\n\n"
  printf "${DIM}Press ${BOLD}Ctrl+C${RESET}${DIM} at any time to cancel.${RESET}\n"

  if ! ask_yesno "Ready to get started?" "y"; then
    info "No problem! Run this script again whenever you're ready."
    exit 0
  fi

  detect_environment       # Step 1
  choose_deployment_mode   # Step 2
  install_dependencies     # Step 3
  configure_openclaw       # Step 4
  install_openclaw         # Step 5
  configure_channels       # Step 6
  verify_and_celebrate     # Step 7
  install_easyclaw_cli     # Step 8

  INSTALL_ABORTED=false    # Prevent cleanup from printing cancellation message

  printf "\n${GREEN}${BOLD}All done! Enjoy OpenClaw 🦞${RESET}\n\n"
  printf "${DIM}If you run into any issues, the full log is at:${RESET}\n"
  printf "  ${BOLD}%s${RESET}\n\n" "${INSTALL_LOG}"
}

main "$@"
