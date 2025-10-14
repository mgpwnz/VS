#!/bin/bash
# ================================================
#   Aztec Sequencer Node Management Script
#   Version: 2.0.4
#   Fully compliant with official directory layout
# ================================================

version="2.0.3"
SERVER_IP=$(wget -qO- eth0.me)

# === Functions ===

# 1️⃣ Create standard directories
prepare_directories() {
    if [[ -d "$HOME/aztec/data" && -d "$HOME/aztec/keys" ]]; then
        read -p "Directories already exist. Recreate? This will delete old data! [y/N]: " resp
        if [[ "$resp" =~ ^[Yy]$ ]]; then
            rm -rf "$HOME/aztec/data" "$HOME/aztec/keys"
        else
            echo "✅ Skipping directory creation."
            return
        fi
    fi
    mkdir -p "$HOME/aztec/data" "$HOME/aztec/keys"
    echo "✅ Directories created at ~/aztec/data and ~/aztec/keys"
}

# 2️⃣ Generate .env (official schema)
generate_env() {
    echo "Generating .env..."
    read -p "Enter Ethereum execution RPC URL(s): " ETHEREUM_HOSTS
    read -p "Enter Beacon consensus URL(s): " L1_CONSENSUS_HOST_URLS

    cat > "$HOME/aztec/.env" <<EOF
DATA_DIRECTORY=./data
KEY_STORE_DIRECTORY=./keys
LOG_LEVEL=info
ETHEREUM_HOSTS=${ETHEREUM_HOSTS}
L1_CONSENSUS_HOST_URLS=${L1_CONSENSUS_HOST_URLS}
P2P_IP=${SERVER_IP}
P2P_PORT=40400
AZTEC_PORT=8080
AZTEC_ADMIN_PORT=8880
EOF

    echo "✅ .env file created at ~/aztec/.env"
}

# 3️⃣ Create keystore(s)
generate_keystore() {
    mkdir -p "$HOME/aztec/keys"
    echo "Select keystore type:"
    select opt in "Single keystore" "Multiple sequencers"; do
        case $opt in
        "Single keystore")
            read -p "Enter attester (private key): " attester
            [[ "$attester" != 0x* ]] && attester="0x$attester"
            read -p "Enter fee recipient (EVM address): " feeRecipient

            cat > "$HOME/aztec/keys/keystore.json" <<EOF
{
  "schemaVersion": 1,
  "validators": [
    {
      "attester": "$attester",
      "feeRecipient": "$feeRecipient"
    }
  ]
}
EOF
            echo "✅ Created ~/aztec/keys/keystore.json"
            break
            ;;
        "Multiple sequencers")
            while true; do
                read -p "Enter sequencer ID (e.g., a/b/c): " name
                read -p "Enter attester (private key): " attester
                [[ "$attester" != 0x* ]] && attester="0x$attester"
                read -p "Enter fee recipient address: " feeRecipient
                cat > "$HOME/aztec/keys/keystore-sequencer-${name}.json" <<EOF
{
  "schemaVersion": 1,
  "validators": [
    {
      "attester": "$attester",
      "feeRecipient": "$feeRecipient"
    }
  ]
}
EOF
                echo "✅ Created keystore-sequencer-${name}.json"
                read -p "Add another sequencer? (y/n): " cont
                [[ "$cont" =~ ^[Nn]$ ]] && break
            done
            break
            ;;
        esac
    done
}

# 4️⃣ Docker Compose (official format)
generate_compose() {
    local image_version=${1:-"aztecprotocol/aztec:$version"}
    cat > "$HOME/aztec/docker-compose.yml" <<EOF
services:
  aztec-sequencer:
    image: "$image_version"
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
    networks:
      - aztec
    restart: always

networks:
  aztec:
    name: aztec
EOF
    echo "✅ docker-compose.yml generated at ~/aztec/docker-compose.yml"
}

# 5️⃣ Install dependencies
install_dependencies() {
    echo "🔧 Installing system dependencies..."
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
        autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
        bsdmainutils ncdu unzip
    . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
}

# 6️⃣ Install Aztec CLI
install_aztec_cli() {
    echo "⬇️ Installing Aztec CLI..."
    curl -sL https://install.aztec.network | bash || { echo "❌ Aztec CLI installation failed"; exit 1; }

    AZTEC_DIR="$HOME/.aztec/bin"
    if ! grep -Fxq "export PATH=\"\\$PATH:$AZTEC_DIR\"" "$HOME/.bashrc"; then
        echo "export PATH=\"\\$PATH:$AZTEC_DIR\"" >>"$HOME/.bashrc"
    fi
    echo "✅ CLI installed. Reload shell with 'source ~/.bashrc'"
}

# 7️⃣ Run Sequencer Node (with directories/env check)
run_sequencer() {
    prepare_directories

    cd "$HOME/aztec" || exit 1

    if [[ ! -f "$HOME/aztec/.env" ]]; then
        echo "❌ .env file не знайдено. Створимо його зараз..."
        generate_env
    fi

    source "$HOME/aztec/.env"

    # Check for keystore files
    if [[ ! -d "$HOME/aztec/keys" || -z $(ls -A "$HOME/aztec/keys") ]]; then
        echo "❌ Keystore files не знайдено. Створимо їх зараз..."
        generate_keystore
    fi

    # Prompt for Docker image
    read -rp "Enter Docker image version (default: aztecprotocol/aztec:$version): " image_ver
    image_ver=${image_ver:-"aztecprotocol/aztec:$version"}

    generate_compose "$image_ver"

    echo "🚀 Starting Aztec Sequencer Node..."
    docker compose up -d
    echo "✅ Node started successfully!"
}

# 8️⃣ Logs, status, update, uninstall
view_logs() { docker logs -f aztec-sequencer --tail 100; }

check_sync() {
    echo "Fetching L2 tip number..."
    curl -s -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
        http://localhost:8080 | jq -r ".result.proven.number"
}

update_node() {
    cd "$HOME/aztec" || exit 1
    read -rp "Enter new version (default: $version): " new_version
    new_version=${new_version:-$version}
    image_version="aztecprotocol/aztec:$new_version"
    echo "⬆️ Updating to $new_version..."
    "$HOME/.aztec/bin/aztec-up" "$new_version"
    docker image pull "$image_version"
    docker compose down || true
    generate_compose "$image_version"
    docker compose up -d
    echo "✅ Updated to version $new_version!"
}

uninstall_node() {
    read -rp "Remove all data and containers? [y/N]: " resp
    if [[ "$resp" =~ ^[Yy]$ ]]; then
        docker compose -f "$HOME/aztec/docker-compose.yml" down -v || true
        rm -rf "$HOME/aztec"
        echo "✅ Aztec Node removed."
    else
        echo "❌ Cancelled."
    fi
}

# === Menu ===
PS3='Select an action: '
options=(
    "Install dependencies"
    "Install Aztec CLI"
    "Generate .env"
    "Generate keystore(s)"
    "Run Sequencer Node"
    "View Logs"
    "Check Sync Status"
    "Update Node"
    "Uninstall Node"
    "Exit"
)

while true; do
    select opt in "${options[@]}"; do
        case $opt in
        "Install dependencies") install_dependencies; break ;;
        "Install Aztec CLI") install_aztec_cli; break ;;
        "Generate .env") generate_env; break ;;
        "Generate keystore(s)") generate_keystore; break ;;
        "Run Sequencer Node") run_sequencer; break ;;
        "View Logs") view_logs; break ;;
        "Check Sync Status") check_sync; break ;;
        "Update Node") update_node; break ;;
        "Uninstall Node") uninstall_node; break ;;
        "Exit") echo "👋 Goodbye!"; exit 0 ;;
        *) echo "Invalid option"; break ;;
        esac
    done
done
