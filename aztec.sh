#!/usr/bin/env bash
# Aztec Sequencer Node Management Script
# Install deps, Aztec CLI, run/manage Sequencer, keys (list/multi-gen), logs, status, update, uninstall.
set -Eeuo pipefail

version="2.1.2"

APP_DIR="$HOME/aztec-sequencer"
ENV_FILE="$APP_DIR/.env"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
CONTAINER_NAME="aztec-sequencer"
NETWORK_NAME="aztec"

# Detect primary public IP
SERVER_IP="$(wget -qO- eth0.me || curl -fsSL ifconfig.me || echo 127.0.0.1)"

# --- helpers ---
say()  { printf "\n\033[1m%s\033[0m\n" "$*"; }
warn() { printf "\n\033[33m⚠ %s\033[0m\n" "$*"; }
err()  { printf "\n\033[31m❌ %s\033[0m\n" "$*"; }

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    say "Installing Docker…"
    . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
  fi
  if ! docker compose version >/dev/null 2>&1; then
    warn "Docker Compose plugin not found — installing (usually part of Docker)."
    . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required. Run 'Install dependencies' first."; return 1
  fi
}

aztec_up() {
  local v="${1:-$version}"
  if [[ -x "$HOME/.aztec/bin/aztec-up" ]]; then
    "$HOME/.aztec/bin/aztec-up" "$v"
  else
    warn "aztec-up not found; install tools first."
  fi
}

write_env() {
  mkdir -p "$APP_DIR"/{keys,data}
  : "${RPC_URL:=${RPC_URL:-}}"
  : "${BEACON_URL:=${BEACON_URL:-}}"

  if [[ -z "${RPC_URL}" ]]; then
    read -r -p "Enter Sepolia RPC URL: " RPC_URL
  fi
  if [[ -z "${BEACON_URL}" ]]; then
    read -r -p "Enter Beacon node URL: " BEACON_URL
  fi

  cat > "$ENV_FILE" <<EOF
DATA_DIRECTORY=./data
KEY_STORE_DIRECTORY=./keys
LOG_LEVEL=info
ETHEREUM_HOSTS=${RPC_URL}
L1_CONSENSUS_HOST_URLS=${BEACON_URL}
P2P_IP=${SERVER_IP}
P2P_PORT=40400
AZTEC_PORT=8080
AZTEC_ADMIN_PORT=8880
EOF
  say "Environment written to $ENV_FILE"
}

write_compose() {
  # requires: image_version set, .env present
  cat > "$COMPOSE_FILE" <<EOF
services:
  aztec-sequencer:
    image: ${image_version}
    container_name: "${CONTAINER_NAME}"
    ports:
      - \${AZTEC_PORT}:\${AZTEC_PORT}
      - \${AZTEC_ADMIN_PORT}:\${AZTEC_ADMIN_PORT}
      - \${P2P_PORT}:\${P2P_PORT}
      - \${P2P_PORT}:\${P2P_PORT}/udp
    volumes:
      - \${DATA_DIRECTORY}:/var/lib/data
      - \${KEY_STORE_DIRECTORY}:/var/lib/keystore
    environment:
      KEY_STORE_DIRECTORY: /var/lib/keystore
      DATA_DIRECTORY: /var/lib/data
      LOG_LEVEL: \${LOG_LEVEL}
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      P2P_IP: \${P2P_IP}
      P2P_PORT: \${P2P_PORT}
      AZTEC_PORT: \${AZTEC_PORT}
      AZTEC_ADMIN_PORT: \${AZTEC_ADMIN_PORT}
    entrypoint: >-
      node
      --no-warnings
      /usr/src/yarn-project/aztec/dest/bin/index.js
      start
      --node
      --archiver
      --sequencer
      --network testnet
    networks:
      - ${NETWORK_NAME}
    restart: always

networks:
  ${NETWORK_NAME}:
    name: ${NETWORK_NAME}
EOF
  say "docker-compose.yml written to $COMPOSE_FILE"
}

install_deps() {
  say "Updating APT and installing packages…"
  sudo apt-get update && sudo apt-get -y upgrade
  sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
    autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
    bsdmainutils ncdu unzip
  require_docker
  say "Dependencies installed."
}

install_aztec_tools() {
  say "Installing Aztec CLI…"
  if ! curl -sL https://install.aztec.network | bash; then
    err "Aztec installation failed"; exit 1
  fi

  AZTEC_DIR="$HOME/.aztec/bin"
  if ! grep -Fq "$AZTEC_DIR" "$HOME/.bashrc"; then
    echo "export PATH=\"\$PATH:$AZTEC_DIR\"" >> "$HOME/.bashrc"
  fi
  say "Aztec CLI added to PATH (reload shell or 'source ~/.bashrc')."

  mkdir -p "$APP_DIR"/{keys,data}
  [[ -f "$ENV_FILE" ]] || write_env
  say "Aztec tools installed."
}

# ---------- Keys utilities ----------
_key_dir_resolve() {
  mkdir -p "$APP_DIR"/{keys,data}
  local KEY_DIR="$APP_DIR/keys"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    local rel="${KEY_STORE_DIRECTORY:-./keys}"
    rel="${rel#./}"
    KEY_DIR="$APP_DIR/$rel"
  fi
  mkdir -p "$KEY_DIR"
  printf "%s" "$KEY_DIR"
}

_extract_coinbase() {
  local f="$1"
  local addr
  addr="$(jq -r '(.feeRecipient // .coinbase // .address // .validator?.coinbase // .validator?.feeRecipient // .account?.address // empty)' "$f" 2>/dev/null || true)"
  if [[ -z "$addr" || "$addr" == "null" ]]; then
    addr="$(grep -aoE '0x[0-9a-fA-F]{40}' "$f" | head -n1 || true)"
  fi
  printf "%s" "${addr:-}"
}

list_keys() {
  require_jq || return 1
  local KEY_DIR; KEY_DIR="$(_key_dir_resolve)"
  say "Keystores in: $KEY_DIR"
  local any=0
  shopt -s nullglob
  for f in "$KEY_DIR"/keystore*.json; do
    any=1
    local cb; cb="$(_extract_coinbase "$f")"
    printf "  %-28s %s\n" "$(basename "$f")" "${cb:-<addr not found>}"
  done
  shopt -u nullglob
  [[ $any -eq 0 ]] && echo "  (none)"
}

secure_keys() {
  local d="$(_key_dir_resolve)"
  chmod 700 "$d"
  find "$d" -type f -name 'keystore*.json' -exec chmod 600 {} \;
  say "Keys secured in $d"
}

_seq_letters() {
  local n="$1" s="" rem
  n=$((n))
  while :; do
    rem=$(( n % 26 ))
    s="$(printf "\\$(printf '%03o' $((97+rem)))")$s"
    n=$(( n / 26 - 1 ))
    [[ $n -lt 0 ]] && break
  done
  printf "%s" "$s"
}

_next_sequencer_filename() {
  local KEY_DIR="$(_key_dir_resolve)"
  local count
  count="$(ls -1 "$KEY_DIR"/keystore-sequencer-*.json 2>/dev/null | wc -l | tr -d ' ')"
  local suffix; suffix="$(_seq_letters "$count")"
  printf "%s/keystore-sequencer-%s.json" "$KEY_DIR" "$suffix"
}

generate_keys_multi() {
  say "Generate multiple validator keys (unique by coinbase / fee-recipient)…"

  local AZTEC_BIN="$HOME/.aztec/bin/aztec"
  if [[ ! -x "$AZTEC_BIN" ]]; then
    err "Aztec CLI not found. Run 'Install Aztec Tools' first."
    return 1
  fi
  require_jq || return 1

  local KEY_DIR; KEY_DIR="$(_key_dir_resolve)"
  list_keys

  # Collect existing coinbase/fee addresses
  declare -A EXIST
  shopt -s nullglob
  for f in "$KEY_DIR"/keystore*.json; do
    cb="$(_extract_coinbase "$f" | tr 'A-F' 'a-f')"
    [[ -n "$cb" ]] && EXIST["$cb"]=1
  done
  shopt -u nullglob

  local n
  read -r -p "How many keys to create? [default 1]: " n
  n="${n:-1}"
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -le 0 ]]; then
    err "Invalid number."; return 1
  fi

  say "You will be asked for:"
  echo "  • FEE-RECIPIENT PRIVATE KEY — this is your Aztec validator private key (starts with 0x...)"
  echo "  • COINBASE ADDRESS — your public wallet address (starts with 0x...)"
  echo "  • MNEMONIC — 12/24-word seed phrase for validator identity"
  echo

  for ((i=1; i<=n; i++)); do
    echo
    say "Key $i of $n"
    local FEE MN COINBASE

    read -r -p "  Enter FEE-RECIPIENT PRIVATE KEY (0x… or plain hex): " FEE
    [[ "$FEE" != 0x* ]] && FEE="0x$FEE"
    if [[ ! "$FEE" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
      err "  Invalid PRIVATE KEY format. Must be 64 hex characters. Skipping."; continue
    fi
    local FEE_lc; FEE_lc="$(tr 'A-F' 'a-f' <<<"$FEE")"
    if [[ -n "${EXIST[$FEE_lc]+x}" ]]; then
      warn "  This private key's fee-recipient already exists. Skipping."
      continue
    fi

    read -r -p "  Enter COINBASE ADDRESS (0x… or plain hex): " COINBASE
    [[ "$COINBASE" != 0x* ]] && COINBASE="0x$COINBASE"
    if [[ ! "$COINBASE" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
      err "  Invalid COINBASE address format. Skipping."; continue
    fi

    read -s -r -p "  Enter MNEMONIC (will not echo): " MN; echo
    if [[ -z "$MN" ]]; then
      err "  Empty mnemonic. Skipping."; continue
    fi

    local OUT; OUT="$(_next_sequencer_filename)"

    "$AZTEC_BIN" validator-keys new \
      --fee-recipient "$FEE" \
      --coinbase "$COINBASE" \
      --mnemonic "$MN" \
      --data-dir "$KEY_DIR" \
      --file "$(basename "$OUT")"

    if [[ -s "$OUT" ]]; then
      local got; got="$(_extract_coinbase "$OUT" | tr 'A-F' 'a-f')"
      if [[ -n "$got" ]]; then
        EXIST["$got"]=1
        say "  ✅ Created $(basename "$OUT")"
        echo "     Fee-Recipient (privkey): $FEE"
        echo "     Coinbase (address):      $COINBASE"
      else
        warn "  Created $(basename "$OUT"), but coinbase not detected."
      fi
    else
      err "  Generation failed for $(basename "$OUT")."
    fi
  done

  echo
  secure_keys
  say "Updated keystore list:"
  list_keys
}

# ---------- Node controls ----------
run_node() {
  require_docker
  [[ -f "$ENV_FILE" ]] || { warn "No .env found — creating…"; write_env; }
  aztec_up "$version"

  if [[ -d "$APP_DIR/data" ]]; then
    read -r -p "Remove old data directory ($APP_DIR/data)? [y/N] " wipe
    if [[ "${wipe:-N}" =~ ^[Yy]$ ]]; then
      rm -rf "$APP_DIR/data"
      say "Old data wiped."
    fi
  fi

  mkdir -p "$APP_DIR"
  cd "$APP_DIR"

  read -r -p "Enter image version [default aztecprotocol/aztec:${version}]: " image_version
  image_version="${image_version:-aztecprotocol/aztec:${version}}"

  write_compose

  if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    say "Stopping existing container…"
    docker stop "$CONTAINER_NAME" >/dev/null
    docker rm "$CONTAINER_NAME" >/dev/null
  fi

  say "Starting Aztec Sequencer Node…"
  docker compose up -d
  say "Done. Use 'View Logs' to tail output."
}

view_logs() {
  if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    say "Tailing last 200 lines (Ctrl+C to quit)…"
    docker logs -f "$CONTAINER_NAME" --tail 200
  else
    warn "Container '$CONTAINER_NAME' is not running."
  fi
}

check_status() {
  say "Container status:"
  if docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -F "$CONTAINER_NAME"; then
    :
  else
    warn "No container named $CONTAINER_NAME found."
  fi

  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    say "Attempting admin health check on 127.0.0.1:${AZTEC_ADMIN_PORT}…"
    if command -v curl >/dev/null 2>&1; then
      (curl -fsS "http://127.0.0.1:${AZTEC_ADMIN_PORT}/health" \
        || curl -fsS "http://127.0.0.1:${AZTEC_ADMIN_PORT}/status" \
        || true) | sed -e 's/^/  /'
    fi
    say "Open ports (matching P2P/AZTEC/ADMIN):"
    ss -lntup | grep -E ":(?:$P2P_PORT|$AZTEC_PORT|$AZTEC_ADMIN_PORT)\b" || true
  else
    warn "No $ENV_FILE — cannot probe ports."
  fi
}

update_node() {
  require_docker
  mkdir -p "$APP_DIR"
  cd "$APP_DIR"

  read -r -p "Enter new version [default ${version}]: " new_version
  new_version="${new_version:-$version}"
  image_version="aztecprotocol/aztec:${new_version}"

  say "Updating Aztec CLI to ${new_version}…"
  aztec_up "$new_version"

  say "Pulling image ${image_version}…"
  docker image pull "$image_version"

  say "Stopping current stack…"
  docker compose -f "$COMPOSE_FILE" down || true

  read -r -p "Clear data directory ($APP_DIR/data)? This resets sync. [y/N] " clr
  if [[ "${clr:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "$APP_DIR/data"
  fi

  write_compose
  say "Starting with new version…"
  docker compose -f "$COMPOSE_FILE" up -d
  say "✅ Node successfully updated to ${new_version}."
}

uninstall_node() {
  read -r -p "Stop and remove stack (keeps keys/data)? [y/N] " resp
  if [[ "${resp:-N}" =~ ^[Yy]$ ]]; then
    docker compose -f "$COMPOSE_FILE" down -v || true
  fi
  read -r -p "Also DELETE data directory ($APP_DIR/data)? [y/N] " wipe_data
  if [[ "${wipe_data:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "$APP_DIR/data"
    say "Data removed."
  fi
  read -r -p "Also DELETE keys directory ($APP_DIR/keys)? [y/N] " wipe_keys
  if [[ "${wipe_keys:-N}" =~ ^[Yy]$ ]]; then
    rm -rf "$APP_DIR/keys"
    say "Keys removed."
  fi
  say "Uninstall complete."
}

# --- menu ---
PS3='Select an action: '
options=(
  "Install dependencies"
  "Install Aztec Tools"
  "List Keys"
  "Generate Validator Keys (multi)"
  "Run Sequencer Node"
  "View Logs"
  "Check Sync Status"
  "Update Node"
  "Uninstall Node"
  "Exit"
)

mkdir -p "$APP_DIR"

while true; do
  select opt in "${options[@]}"; do
    case "$opt" in
      "Install dependencies")              install_deps; break ;;
      "Install Aztec Tools")               install_aztec_tools; break ;;
      "List Keys")                         list_keys; break ;;
      "Generate Validator Keys (multi)")   generate_keys_multi; break ;;
      "Run Sequencer Node")                run_node; break ;;
      "View Logs")                         view_logs; break ;;
      "Check Sync Status")                 check_status; break ;;
      "Update Node")                       update_node; break ;;
      "Uninstall Node")                    uninstall_node; break ;;
      "Exit")                              echo "Goodbye!"; exit 0 ;;
      *) echo "Invalid option. Try again." ;;
    esac
  done
done
