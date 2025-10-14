#!/bin/bash
# ===============================================
# Aztec Sequencer Node Manager
# Unified keystore.json + .env interactive script
# ===============================================

AZTEC_DIR="aztec"
KEYS_DIR="$AZTEC_DIR/keys"
DATA_DIR="$AZTEC_DIR/data"
ENV_FILE="$AZTEC_DIR/.env"
KEYSTORE_FILE="$KEYS_DIR/keystore.json"
DOCKER_COMPOSE_FILE="$AZTEC_DIR/docker-compose.yml"

# -----------------------------------------------
# Helper: show menu header
# -----------------------------------------------
function header() {
  clear
  echo "==============================================="
  echo "        🚀 AZTEC SEQUENCER MANAGER"
  echo "==============================================="
}

# -----------------------------------------------
# Create directories and .env file
# -----------------------------------------------
function prepare_env() {
  header
  echo "Preparing directories and .env file..."
  mkdir -p "$KEYS_DIR" "$DATA_DIR"

  if [ -f "$ENV_FILE" ]; then
    echo ".env already exists."
    echo "1) Show current .env"
    echo "2) Edit parameters"
    echo "3) Regenerate from scratch"
    echo "4) Back"
    read -p "Select an option: " opt
    case $opt in
      1)
        echo
        cat "$ENV_FILE"
        read -p "Press enter to return..."
        return
        ;;
      2)
        edit_env
        return
        ;;
      3)
        rm "$ENV_FILE"
        ;;
      4)
        return
        ;;
      *)
        echo "Invalid option."
        return
        ;;
    esac
  fi

  echo "Creating new .env configuration..."
  read -p "Enter Ethereum hosts (comma-separated): " ETHEREUM_HOSTS
  read -p "Enter L1 Consensus URLs (comma-separated): " L1_CONSENSUS_HOST_URLS
  read -p "Enter your public IP (P2P_IP): " P2P_IP
  read -p "Enter P2P port [40400]: " P2P_PORT
  P2P_PORT=${P2P_PORT:-40400}
  read -p "Enter Aztec port [8080]: " AZTEC_PORT
  AZTEC_PORT=${AZTEC_PORT:-8080}
  read -p "Enter Aztec admin port [8880]: " AZTEC_ADMIN_PORT
  AZTEC_ADMIN_PORT=${AZTEC_ADMIN_PORT:-8880}

  cat > "$ENV_FILE" <<EOF
DATA_DIRECTORY=./data
KEY_STORE_DIRECTORY=./keys
LOG_LEVEL=info
ETHEREUM_HOSTS=$ETHEREUM_HOSTS
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS_HOST_URLS
P2P_IP=$P2P_IP
P2P_PORT=$P2P_PORT
AZTEC_PORT=$AZTEC_PORT
AZTEC_ADMIN_PORT=$AZTEC_ADMIN_PORT
EOF

  echo ".env created successfully!"
  read -p "Press enter to return..."
}

# -----------------------------------------------
# Edit existing .env
# -----------------------------------------------
function edit_env() {
  echo
  echo "Editing .env..."
  nano "$ENV_FILE"
  echo "Saved."
  read -p "Press enter to return..."
}

# -----------------------------------------------
# Manage unified keystore.json
# -----------------------------------------------
function manage_keystore() {
  header
  mkdir -p "$KEYS_DIR"

  if [ -f "$KEYSTORE_FILE" ]; then
    echo "Keystore found: $KEYSTORE_FILE"
    echo "1) Show existing validators"
    echo "2) Add new validator"
    echo "3) Edit existing validator"
    echo "4) Regenerate file (overwrite)"
    echo "5) Back"
    read -p "Select option: " kopt

    case $kopt in
      1)
        jq '.' "$KEYSTORE_FILE"
        read -p "Press enter to return..."
        ;;
      2)
        add_validator
        ;;
      3)
        edit_validator
        ;;
      4)
        rm "$KEYSTORE_FILE"
        create_keystore
        ;;
      5)
        return
        ;;
      *)
        echo "Invalid option."
        ;;
    esac
  else
    create_keystore
  fi
}

# -----------------------------------------------
# Create new keystore.json
# -----------------------------------------------
function create_keystore() {
  echo "Creating new keystore.json..."
  validators=()

  while true; do
    read -p "Enter attester private key (or leave empty to stop): " attester
    [ -z "$attester" ] && break
    read -p "Enter fee recipient address: " fee
    validators+=("{\"attester\": \"$attester\", \"feeRecipient\": \"$fee\"}")
  done

  local joined=$(IFS=,; echo "${validators[*]}")

  cat > "$KEYSTORE_FILE" <<EOF
{
  "schemaVersion": 1,
  "validators": [
    $joined
  ]
}
EOF
  echo "Keystore created successfully!"
  read -p "Press enter to return..."
}

# -----------------------------------------------
# Add new validator to existing keystore
# -----------------------------------------------
function add_validator() {
  echo "Adding new validator..."
  read -p "Enter attester private key: " attester
  read -p "Enter fee recipient address: " fee

  tmpfile=$(mktemp)
  jq ".validators += [{\"attester\": \"$attester\", \"feeRecipient\": \"$fee\"}]" "$KEYSTORE_FILE" > "$tmpfile" && mv "$tmpfile" "$KEYSTORE_FILE"

  echo "Validator added successfully!"
  read -p "Press enter to return..."
}

# -----------------------------------------------
# Edit existing validator
# -----------------------------------------------
function edit_validator() {
  count=$(jq '.validators | length' "$KEYSTORE_FILE")
  if [ "$count" -eq 0 ]; then
    echo "No validators found."
    read -p "Press enter to return..."
    return
  fi

  echo "Existing validators:"
  jq -r '.validators | to_entries[] | "\(.key): \(.value.attester) -> \(.value.feeRecipient)"' "$KEYSTORE_FILE"
  read -p "Select index to edit (0-$((count-1))): " idx
  [ -z "$idx" ] && return
  read -p "Enter new attester key (leave blank to keep): " new_att
  read -p "Enter new fee recipient (leave blank to keep): " new_fee

  tmpfile=$(mktemp)
  jq --argjson i "$idx" --arg att "$new_att" --arg fee "$new_fee" '
    .validators[$i].attester = (if $att != "" then $att else .validators[$i].attester end) |
    .validators[$i].feeRecipient = (if $fee != "" then $fee else .validators[$i].feeRecipient end)
  ' "$KEYSTORE_FILE" > "$tmpfile" && mv "$tmpfile" "$KEYSTORE_FILE"

  echo "Validator updated successfully!"
  read -p "Press enter to return..."
}

# -----------------------------------------------
# Run Aztec Sequencer Node
# -----------------------------------------------
function run_node() {
  header
  echo "Starting Aztec Sequencer Node..."

  # Ensure env and keystore exist
  [ ! -f "$ENV_FILE" ] && prepare_env
  [ ! -f "$KEYSTORE_FILE" ] && manage_keystore

  echo "✅ Using existing .env and keystore.json"

  # Write docker-compose if missing
  if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    cat > "$DOCKER_COMPOSE_FILE" <<EOF
services:
  aztec-sequencer:
    image: "aztecprotocol/aztec:2.0.2"
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
    restart: always
EOF
  fi

  cd "$AZTEC_DIR"
  docker compose down || true
  docker compose up -d
  cd ..

  echo "✅ Aztec Sequencer Node is running!"
  read -p "Press enter to return..."
}

# -----------------------------------------------
# Main menu
# -----------------------------------------------
while true; do
  header
  echo "1) Prepare environment (.env)"
  echo "2) Manage keystore.json"
  echo "3) Run Sequencer Node"
  echo "4) Exit"
  echo "-----------------------------------------------"
  read -p "Select an action: " action
  case $action in
    1) prepare_env ;;
    2) manage_keystore ;;
    3) run_node ;;
    4) exit 0 ;;
    *) echo "Invalid option."; sleep 1 ;;
  esac
done
