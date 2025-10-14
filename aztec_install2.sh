#!/bin/bash
# Aztec Sequencer/Validator Multi-Instance Manager
# Author: you + ChatGPT
# Version of Aztec image/CLI to use by default:
version="2.0.3"

set -u
# Comment the set -e if you prefer the script to continue on non-critical errors
#set -e

# Detect server public IP (fallback to hostname -I first non-loopback)
SERVER_IP=$(wget -qO- eth0.me 2>/dev/null || true)
if [[ -z "${SERVER_IP}" ]]; then
  SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi

# ====== Helpers ======
bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
rpc_port_for(){ local id=$1; echo $((8080 + id*10)); }
metrics_port_for(){ local id=$1; echo $((8880 + id*10)); }
p2p_port_for(){ local id=$1; echo $((40400 + id)); }

ensure_base_dirs(){
  mkdir -p "$HOME/aztec"
  mkdir -p "$HOME/.aztec/bin"
}

require_env_base(){
  local ENV_FILE_BASE="$HOME/.env.aztec"
  if [[ ! -f "$ENV_FILE_BASE" ]]; then
    echo "❌ $ENV_FILE_BASE not found. Run 'Install Aztec Tools' first."
    return 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE_BASE"
}

# Create per-instance env if missing; ensure keys present
ensure_instance_env(){
  local id=$1
  local ENV_FILE_BASE="$HOME/.env.aztec"
  local ENV_FILE="$HOME/.env.aztec.$id"
  if [[ ! -f "$ENV_FILE_BASE" ]]; then
    echo "❌ Base env ($ENV_FILE_BASE) missing."; return 1
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE_BASE" "$ENV_FILE"
    echo "# Instance-specific variables for id=$id" >> "$ENV_FILE"
  fi

  # shellcheck disable=SC1090
  source "$ENV_FILE"

  if [[ -z "${private_key:-}" ]]; then
    read -rp "Validator private key for instance $id (0x...): " pk
    [[ "$pk" != 0x* ]] && pk="0x$pk"
    echo "private_key=\"$pk\"" >> "$ENV_FILE"
  fi
  if [[ -z "${public_key:-}" ]]; then
    read -rp "EVM address (COINBASE) for instance $id (0x...): " addr
    echo "public_key=\"$addr\"" >> "$ENV_FILE"
  fi

  # Reload to get just-written vars
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

# Compose generator for a given instance ID
container(){
  local id="$1"         # 0,1,2...
  local image_version="$2"
  local RPC_URL="$3"
  local BEACON_URL="$4"
  local private_key="$5"
  local public_key="$6"

  local RPC_PORT; RPC_PORT=$(rpc_port_for "$id")
  local METRICS_PORT; METRICS_PORT=$(metrics_port_for "$id")
  local P2P_PORT; P2P_PORT=$(p2p_port_for "$id")

  local DATA_DIR="$HOME/.aztec/alpha-testnet/data-$id"
  mkdir -p "$HOME/aztec/$id"
  mkdir -p "$DATA_DIR"

  cat > "$HOME/aztec/$id/docker-compose.yml" <<EOF
services:
  aztec-node:
    container_name: aztec-sequencer-$id
    image: ${image_version}
    restart: unless-stopped
    environment:
      ETHEREUM_HOSTS: ${RPC_URL}
      L1_CONSENSUS_HOST_URLS: ${BEACON_URL}
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEY: ${private_key}
      COINBASE: ${public_key}
      P2P_IP: ${SERVER_IP}
      LOG_LEVEL: info
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network testnet --node --archiver --sequencer'
    ports:
      - "${P2P_PORT}:${P2P_PORT}/tcp"
      - "${P2P_PORT}:${P2P_PORT}/udp"
      - "${RPC_PORT}:8080"
      - "${METRICS_PORT}:8880"
    volumes:
      - "${DATA_DIR}:/data"
EOF
}

list_instances(){
  echo
  bold "Running Aztec containers:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E '^aztec-sequencer-' || echo "  (none)"
  echo
  bold "Configured instances on disk:"
  ls -1 "$HOME/aztec" 2>/dev/null | grep -E '^[0-9]+$' | sed 's/^/  id=/' || echo "  (none)"
  echo
}

ensure_docker(){
  if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker..."
    . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
  fi
}

aztec_up(){
  "$HOME/.aztec/bin/aztec-up" "$1"
}

# ====== Menu actions ======
install_deps(){
  echo "Updating and installing packages..."
  sudo apt-get update && sudo apt-get upgrade -y
  sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
      autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
      bsdmainutils ncdu unzip
  ensure_docker
}

install_tools(){
  echo "Installing Aztec CLI..."
  curl -sL https://install.aztec.network | bash || { echo "❌ Aztec installation failed"; return 1; }
  local AZTEC_DIR="$HOME/.aztec/bin"
  if ! grep -Fxq "export PATH=\"\\$PATH:$AZTEC_DIR\"" "$HOME/.bashrc"; then
    echo "export PATH=\"\\$PATH:$AZTEC_DIR\"" >> "$HOME/.bashrc"
  fi
  echo "✅ Aztec CLI added to PATH. (Run 'source ~/.bashrc' or open a new shell.)"

  local ENV_FILE="$HOME/.env.aztec"
  [[ -f "$ENV_FILE" ]] && . "$ENV_FILE"

  if [[ -z "${RPC_URL:-}" ]]; then
    read -p "Enter Sepolia RPC URL: " RPC_URL
    echo "RPC_URL=\"$RPC_URL\"" >> "$ENV_FILE"
  fi
  if [[ -z "${BEACON_URL:-}" ]]; then
    read -p "Enter Beacon node URL: " BEACON_URL
    echo "BEACON_URL=\"$BEACON_URL\"" >> "$ENV_FILE"
  fi
  if [[ -z "${private_key:-}" ]]; then
    read -p "Enter your validator private key: " private_key
    [[ "$private_key" != 0x* ]] && private_key="0x$private_key"
    echo "private_key=\"$private_key\"" >> "$ENV_FILE"
  fi
  if [[ -z "${public_key:-}" ]]; then
    read -p "Enter your EVM address (public key): " public_key
    echo "public_key=\"$public_key\"" >> "$ENV_FILE"
  fi
  echo "✅ Base env saved at $HOME/.env.aztec"
}

run_single(){
  require_env_base || return 1
  aztec_up "$version"

  read -rp "Image version (default: aztecprotocol/aztec:${version}): " image_version
  image_version=${image_version:-aztecprotocol/aztec:"$version"}

  local id=0
  local ENV_FILE="$HOME/.env.aztec.$id"
  ensure_instance_env "$id" || return 1
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  # Clean only instance-0 data (not global wipe)
  local DATA_DIR="$HOME/.aztec/alpha-testnet/data-$id"
  rm -rf "$DATA_DIR"

  container "$id" "$image_version" "$RPC_URL" "$BEACON_URL" "$private_key" "$public_key"
  (cd "$HOME/aztec/$id" && docker compose up -d)

  echo "✅ Instance #$id started"
  echo "    RPC:     http://localhost:$(rpc_port_for $id)"
  echo "    Metrics: http://localhost:$(metrics_port_for $id)"
  echo "    P2P:     $(p2p_port_for $id)/tcp+udp"
}

run_multiple(){
  require_env_base || return 1
  aztec_up "$version"

  read -rp "Image version (default: aztecprotocol/aztec:${version}): " image_version
  image_version=${image_version:-aztecprotocol/aztec:"$version"}

  read -rp "How many instances to run? (e.g., 2): " COUNT
  COUNT=${COUNT:-1}

  for (( id=0; id<COUNT; id++ )); do
    local ENV_FILE="$HOME/.env.aztec.$id"
    ensure_instance_env "$id" || return 1
    # shellcheck disable=SC1090
    source "$ENV_FILE"

    # stop & remove if exists
    docker ps -q --filter "name=aztec-sequencer-$id" | xargs -r docker stop
    docker ps -a -q --filter "name=aztec-sequencer-$id" | xargs -r docker rm
    rm -rf "$HOME/.aztec/alpha-testnet/data-$id"

    container "$id" "$image_version" "$RPC_URL" "$BEACON_URL" "$private_key" "$public_key"
    (cd "$HOME/aztec/$id" && docker compose up -d)
    echo "✅ Instance #$id started | RPC: $(rpc_port_for $id) | Metrics: $(metrics_port_for $id) | P2P: $(p2p_port_for $id)"
  done
}

view_logs(){
  read -rp "Instance ID to tail logs (e.g., 0): " id
  docker logs -f "aztec-sequencer-$id" --tail 100
}

check_sync(){
  read -rp "Instance ID to query (e.g., 0): " id
  local PORT; PORT=$(rpc_port_for "$id")
  echo "Fetching L2 tip number from RPC :$PORT ..."
  curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
      "http://localhost:${PORT}" | jq -r ".result.proven.number"
}

generate_proof(){
  read -rp "Instance ID to use (e.g., 0): " id
  local PORT; PORT=$(rpc_port_for "$id")
  echo "Getting block number..."
  local BLOCK_NUMBER
  BLOCK_NUMBER=$(curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
      "http://localhost:${PORT}" | jq -r ".result.proven.number")
  echo "Block number: $BLOCK_NUMBER"

  echo "Generating proof via node_getArchiveSiblingPath..."
  curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK_NUMBER\",\"$BLOCK_NUMBER\"],\"id\":67}" \
      "http://localhost:${PORT}" | jq -r ".result"
}

update_node(){
  require_env_base || return 1
  read -rp "New version (default: $version): " new_version
  new_version=${new_version:-$version}
  local image_version="aztecprotocol/aztec:$new_version"
  echo "Updating aztec CLI to $new_version..."
  aztec_up "$new_version"

  echo "Pulling image $image_version ..."
  docker image pull "$image_version" || true

  echo
  bold "Restart which instances?"
  echo "1) All running"
  echo "2) Specific ID"
  read -rp "Choose [1/2]: " choice

  if [[ "$choice" == "2" ]]; then
    read -rp "Instance ID to restart: " id
    local ENV_FILE="$HOME/.env.aztec.$id"
    if [[ ! -f "$ENV_FILE" ]]; then echo "No env for id=$id"; return 1; fi
    # shellcheck disable=SC1090
    source "$ENV_FILE"

    docker ps -q --filter "name=aztec-sequencer-$id" | xargs -r docker stop
    docker ps -a -q --filter "name=aztec-sequencer-$id" | xargs -r docker rm
    rm -rf "$HOME/.aztec/alpha-testnet/data-$id"

    container "$id" "$image_version" "$RPC_URL" "$BEACON_URL" "$private_key" "$public_key"
    (cd "$HOME/aztec/$id" && docker compose up -d)
    echo "✅ Instance #$id updated & restarted."
  else
    # All running: detect by docker
    local running_ids
    running_ids=$(docker ps --format '{{.Names}}' | sed -n 's/^aztec-sequencer-\([0-9]\+\)$/\1/p')
    if [[ -z "$running_ids" ]]; then
      echo "No running instances detected."
      return 0
    fi
    for id in $running_ids; do
      local ENV_FILE="$HOME/.env.aztec.$id"
      if [[ ! -f "$ENV_FILE" ]]; then
        echo "Skip id=$id (no env)"; continue
      fi
      # shellcheck disable=SC1090
      source "$ENV_FILE"

      docker stop "aztec-sequencer-$id" || true
      docker rm "aztec-sequencer-$id" || true
      rm -rf "$HOME/.aztec/alpha-testnet/data-$id"

      container "$id" "$image_version" "$RPC_URL" "$BEACON_URL" "$private_key" "$public_key"
      (cd "$HOME/aztec/$id" && docker compose up -d)
      echo "✅ Instance #$id updated & restarted."
    done
  fi
}

stop_remove_instance(){
  read -rp "Instance ID to stop/remove (e.g., 0): " id
  read -rp "Also delete data dir for this instance? [y/N]: " wipe
  docker stop "aztec-sequencer-$id" 2>/dev/null || true
  docker rm "aztec-sequencer-$id" 2>/dev/null || true
  if [[ "$wipe" =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/.aztec/alpha-testnet/data-$id"
    echo "🧹 Data for id=$id removed."
  fi
  echo "✅ Instance #$id stopped/removed."
}

uninstall_all(){
  read -rp "Wipe ALL data and remove ALL Aztec project directories? [y/N] " response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    docker ps -a --format '{{.Names}}' | grep -E '^aztec-sequencer-' | xargs -r docker stop
    docker ps -a --format '{{.Names}}' | grep -E '^aztec-sequencer-' | xargs -r docker rm
    rm -rf "$HOME/aztec"
    rm -rf "$HOME/.aztec/alpha-testnet"
    echo "Aztec containers and data removed."
  else
    echo "Uninstallation cancelled."
  fi
}

# ====== Menu ======
ensure_base_dirs

PS3='Select an action: '
options=(
  "Install dependencies"
  "Install Aztec Tools"
  "Run Sequencer Node (id=0)"
  "Run Multiple Sequencers"
  "List Instances & Ports"
  "View Logs"
  "Check Sync Status"
  "Generate Proof"
  "Update Node"
  "Stop/Remove Instance"
  "Uninstall ALL"
  "Exit"
)

while true; do
  select opt in "${options[@]}"; do
    case $opt in
      "Install dependencies") install_deps; break;;
      "Install Aztec Tools") install_tools; break;;
      "Run Sequencer Node (id=0)") run_single; break;;
      "Run Multiple Sequencers") run_multiple; break;;
      "List Instances & Ports") list_instances; break;;
      "View Logs") view_logs; break;;
      "Check Sync Status") check_sync; break;;
      "Generate Proof") generate_proof; break;;
      "Update Node") update_node; break;;
      "Stop/Remove Instance") stop_remove_instance; break;;
      "Uninstall ALL") uninstall_all; break;;
      "Exit") echo "Goodbye!"; exit 0;;
      *) echo "Invalid option. Try again.";;
    esac
  done
done
