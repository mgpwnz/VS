#!/usr/bin/env bash
# Aztec Sequencer Node Manager
# Version: 2.0.5
# English comments and prompts
# Supports: .env management, keystore management, run/update/uninstall

set -euo pipefail

# Config
VERSION="2.0.3"
PROJECT_DIR="$HOME/aztec"
KEYS_DIR="$PROJECT_DIR/keys"
DATA_DIR="$PROJECT_DIR/data"
ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
SERVER_IP="$(wget -qO- eth0.me || echo "127.0.0.1")"
DEFAULT_IMAGE="aztecprotocol/aztec:${VERSION}"
EDITOR="${EDITOR:-nano}"

# Ensure project dirs exist (but do not overwrite)
ensure_dirs() {
  mkdir -p "$PROJECT_DIR" "$KEYS_DIR" "$DATA_DIR"
}

# ---------- .env utilities ----------
create_env_interactive() {
  echo "Create new .env (will overwrite if exists). Press ENTER to accept empty value."
  read -rp "Enter Ethereum execution RPC URL(s) (comma-separated): " ETHEREUM_HOSTS
  read -rp "Enter L1 consensus (Beacon) URL(s) (comma-separated): " L1_CONSENSUS_HOST_URLS
  read -rp "P2P_IP [default: detected $SERVER_IP]: " P2P_IP_INPUT
  P2P_IP="${P2P_IP_INPUT:-$SERVER_IP}"
  cat > "$ENV_FILE" <<EOF
DATA_DIRECTORY=./data
KEY_STORE_DIRECTORY=./keys
LOG_LEVEL=info
ETHEREUM_HOSTS=${ETHEREUM_HOSTS}
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS}
P2P_IP=${P2P_IP}
P2P_PORT=40400
AZTEC_PORT=8080
AZTEC_ADMIN_PORT=8880
EOF
  echo "✅ Created $ENV_FILE"
}

show_env() {
  if [[ -f "$ENV_FILE" ]]; then
    echo "---- $ENV_FILE ----"
    sed -n '1,200p' "$ENV_FILE"
    echo "-------------------"
  else
    echo "No .env present at $ENV_FILE"
  fi
}

edit_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env not found — create it first."
    read -rp "Create .env now? [y/N]: " r
    [[ "$r" =~ ^[Yy]$ ]] && create_env_interactive || return
  fi
  "$EDITOR" "$ENV_FILE"
  echo "✅ Edited $ENV_FILE"
}

env_menu() {
  while true; do
    echo
    echo "=== .env management ==="
    PS3="Select .env action: "
    options=("Show .env" "Edit .env" "Regenerate .env (overwrite)" "Back")
    select choice in "${options[@]}"; do
      case $REPLY in
        1) show_env; break ;;
        2) edit_env; break ;;
        3)
           read -rp "This will overwrite existing .env. Continue? [y/N]: " resp
           if [[ "$resp" =~ ^[Yy]$ ]]; then
             create_env_interactive
           else
             echo "Cancelled."
           fi
           break
           ;;
        4) return ;;
        *) echo "Invalid choice"; break ;;
      esac
    done
  done
}

# ---------- Keystore utilities ----------
list_keystores() {
  echo "Keystore files in $KEYS_DIR:"
  ls -1 "$KEYS_DIR"/keystore*.json 2>/dev/null || echo "(none)"
}

show_keystore_file() {
  list_keystores
  read -rp "Enter filename to view (or blank to cancel): " file
  [[ -z "$file" ]] && return
  # allow both absolute and name
  if [[ ! -f "$file" ]]; then
    file="$KEYS_DIR/$file"
  fi
  if [[ -f "$file" ]]; then
    echo "---- $file ----"
    jq . "$file" 2>/dev/null || sed -n '1,200p' "$file"
    echo "----------------"
  else
    echo "File not found: $file"
  fi
}

add_single_keystore() {
  read -rp "Enter attester (private key, 0x...): " att
  [[ "$att" != 0x* ]] && att="0x$att"
  read -rp "Enter feeRecipient (address, 0x...): " fee
  cat > "$KEYS_DIR/keystore.json" <<EOF
{
  "schemaVersion": 1,
  "validators": [
    {
      "attester": "$att",
      "feeRecipient": "$fee"
    }
  ]
}
EOF
  echo "✅ Created $KEYS_DIR/keystore.json"
}

add_sequencer_keystore() {
  read -rp "Enter sequencer id (short suffix, e.g. a or node01): " id
  read -rp "Enter attester (private key, 0x...): " att
  [[ "$att" != 0x* ]] && att="0x$att"
  read -rp "Enter feeRecipient (address, 0x...): " fee
  file="$KEYS_DIR/keystore-sequencer-$id.json"
  cat > "$file" <<EOF
{
  "schemaVersion": 1,
  "validators": [
    {
      "attester": "$att",
      "feeRecipient": "$fee"
    }
  ]
}
EOF
  echo "✅ Created $file"
}

edit_keystore_file() {
  list_keystores
  read -rp "Enter keystore filename to edit (e.g. keystore.json or keystore-sequencer-a.json) or blank to cancel: " fname
  [[ -z "$fname" ]] && return
  # normalize to full path if necessary
  if [[ ! -f "$fname" ]]; then
    fname="$KEYS_DIR/$fname"
  fi
  if [[ -f "$fname" ]]; then
    "$EDITOR" "$fname"
    echo "✅ Edited $fname"
  else
    echo "File not found: $fname"
  fi
}

keystore_menu() {
  ensure_dirs
  while true; do
    echo
    echo "=== Keystore management ==="
    PS3="Select keystore action: "
    options=("List keystores" "Show keystore" "Add single keystore" "Add sequencer keystore" "Edit keystore" "Back")
    select opt in "${options[@]}"; do
      case $REPLY in
        1) list_keystores; break ;;
        2) show_keystore_file; break ;;
        3) add_single_keystore; break ;;
        4)
           while true; do
             add_sequencer_keystore
             read -rp "Add another sequencer keystore? [y/N]: " more
             [[ ! "$more" =~ ^[Yy]$ ]] && break
           done
           break
           ;;
        5) edit_keystore_file; break ;;
        6) return ;;
        *) echo "Invalid option"; break ;;
      esac
    done
  done
}

# ---------- Docker Compose generation ----------
generate_compose() {
  # require .env present
  if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env missing; generate .env first."
    return 1
  fi

  # read .env into current environment, but don't export persistently
  # using a subshell 'source' to avoid polluting
  # read lines like KEY=VAL
  set -o allexport
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +o allexport

  # choose image
  read -rp "Enter Docker image (default: $DEFAULT_IMAGE): " image
  image=${image:-$DEFAULT_IMAGE}

  cat > "$COMPOSE_FILE" <<EOF
version: "3.9"
services:
  aztec-sequencer:
    image: "$image"
    container_name: "aztec-sequencer"
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
    restart: unless-stopped
EOF

  echo "✅ Generated $COMPOSE_FILE"
}

# ---------- Run / restart ----------
run_sequencer_flow() {
  ensure_dirs

  # .env check
  if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env not found. Creating .env now."
    create_env_interactive
  else
    echo ".env found at $ENV_FILE (will be used)."
  fi

  # keystore check
  existing=$(ls "$KEYS_DIR"/keystore*.json 2>/dev/null || true)
  if [[ -z "$existing" ]]; then
    echo "No keystore files found. Creating keystore(s) now."
    keystore_menu
  else
    echo "Keystore files found (will be used):"
    ls -1 "$KEYS_DIR"/keystore*.json
    read -rp "Do you want to add or edit keystore files before starting? [y/N]: " kresp
    if [[ "$kresp" =~ ^[Yy]$ ]]; then
      keystore_menu
    fi
  fi

  # generate compose (overwrites)
  generate_compose

  # stop existing -> start
  echo "Bringing down previous compose (if any)..."
  (cd "$PROJECT_DIR" && docker compose down) || true

  echo "Starting compose..."
  (cd "$PROJECT_DIR" && docker compose up -d)

  echo "✅ Aztec sequencer started (container: aztec-sequencer)."
}

# ---------- Misc utilities ----------
install_dependencies() {
  echo "Installing dependencies (docker + common tools)..."
  sudo apt-get update && sudo apt-get upgrade -y
  sudo apt-get install -y curl wget jq git lz4 unzip nano
  # docker install helper (optional)
  . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh) || true
  echo "✅ Dependencies installed (or attempted)."
}

view_logs() {
  echo "Tailing logs for aztec-sequencer (Ctrl+C to stop)..."
  docker logs -f aztec-sequencer --tail 200
}

check_sync() {
  echo "Querying L2 tip number from local sequencer RPC (http://localhost:8080)..."
  curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
    http://localhost:8080 | jq -r ".result.proven.number"
}

update_node_flow() {
  ensure_dirs
  read -rp "Enter new image version (tag only, e.g. 2.0.3) or full image: " newimg
  if [[ -z "$newimg" ]]; then
    echo "No image supplied; aborting."
    return
  fi
  # allow user to pass full image or tag
  if [[ "$newimg" =~ ^aztecprotocol/aztec: ]]; then
    image="$newimg"
  else
    image="aztecprotocol/aztec:${newimg}"
  fi
  echo "Updating compose to image: $image"
  # regenerate compose with new image
  # inject image as first arg to generate_compose
  # temporary set DEFAULT_IMAGE
  DEFAULT_IMAGE_OLD="$DEFAULT_IMAGE"
  DEFAULT_IMAGE="$image"
  generate_compose
  DEFAULT_IMAGE="$DEFAULT_IMAGE_OLD"
  # restart stack
  (cd "$PROJECT_DIR" && docker compose down) || true
  (cd "$PROJECT_DIR" && docker compose up -d)
  echo "✅ Updated and restarted with $image"
}

uninstall_flow() {
  read -rp "This will stop containers and remove $PROJECT_DIR. Continue? [y/N]: " resp
  if [[ "$resp" =~ ^[Yy]$ ]]; then
    (cd "$PROJECT_DIR" && docker compose down -v) || true
    rm -rf "$PROJECT_DIR"
    echo "✅ Removed project directory and containers."
  else
    echo "Cancelled."
  fi
}

# ---------- Main menu ----------
main_menu() {
  PS3="Select an action: "
  options=(
    "Install dependencies"
    ".env management"
    "Keystore management"
    "Run Sequencer Node (down -> up)"
    "View Logs"
    "Check Sync Status"
    "Update Node (change image)"
    "Uninstall (remove project)"
    "Exit"
  )

  while true; do
    echo
    echo "==== Aztec Sequencer Manager (v${VERSION}) ===="
    select opt in "${options[@]}"; do
      case $REPLY in
        1) install_dependencies; break ;;
        2) env_menu; break ;;
        3) keystore_menu; break ;;
        4) run_sequencer_flow; break ;;
        5) view_logs; break ;;
        6) check_sync; break ;;
        7) update_node_flow; break ;;
        8) uninstall_flow; break ;;
        9) echo "Bye."; exit 0 ;;
        *) echo "Invalid selection"; break ;;
      esac
    done
  done
}

# Entrypoint
ensure_dirs
main_menu
