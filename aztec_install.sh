#!/bin/bash
# Aztec Sequencer Node Management Script
# This script allows you to install dependencies, Aztec CLI tools,
# run & manage the Aztec Sequencer Node, view logs, check sync status,
# generate proofs, update, or uninstall the node.

PS3='Select an action: '
options=(
  "Install dependencies"
  "Install Aztec Tools"
  "Run Sequencer Node"
  "View Logs"
  "Check Sync Status"
  "Generate Proof"
  "Update Node"
  "Uninstall Node"
  "Exit"
)

while true; do
  select opt in "${options[@]}"; do
    case $opt in
      "Install dependencies")
        echo "Updating package lists and installing required packages..."
        sudo apt-get update && sudo apt-get upgrade -y
        sudo apt-get install -y \
          curl iptables build-essential git wget lz4 jq make gcc nano automake \
          autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev \
          tar clang bsdmainutils ncdu unzip
        # Install Docker if not already present
        . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
        break
        ;;

      "Install Aztec Tools")
        echo "Installing Aztec CLI..."
        curl -sL https://install.aztec.network | bash || { echo "❌ Aztec installation failed"; exit 1; }

        # Add Aztec CLI to PATH if missing
        AZTEC_DIR="$HOME/.aztec/bin"
        if ! grep -Fxq "export PATH=\"\\$PATH:$AZTEC_DIR\"" "$HOME/.bashrc"; then
          echo "export PATH=\"\\$PATH:$AZTEC_DIR\"" >> "$HOME/.bashrc"
        fi
        # Reload
        source "$HOME/.bashrc"

        # Source or create env file
        ENV_FILE="$HOME/.env.aztec"
        [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

        # Prompt for required variables
        [[ -z "$RPC_URL" ]] && read -p "Enter Sepolia RPC URL: " RPC_URL && echo "RPC_URL=$RPC_URL" >> "$ENV_FILE"
        [[ -z "$BEACON_URL" ]] && read -p "Enter Beacon node URL: " BEACON_URL && echo "BEACON_URL=$BEACON_URL" >> "$ENV_FILE"
        if [[ -z "$private_key" ]]; then
          read -p "Enter your validator private key: " private_key
          [[ "$private_key" != 0x* ]] && private_key="0x$private_key"
          echo "private_key=$private_key" >> "$ENV_FILE"
        fi
        [[ -z "$public_key" ]] && read -p "Enter your EVM address (public key): " public_key && echo "public_key=$public_key" >> "$ENV_FILE"
        break
        ;;

      "Run Sequencer Node")
        echo "Cleaning up existing Aztec Sequencer Node (if any)..."
        # Stop and remove existing containers
        docker ps -q --filter "ancestor=aztecprotocol/aztec" | xargs -r docker stop | xargs -r docker rm

        # Kill tmux session 'aztec' if exists
        tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -qx "aztec" && tmux kill-session -t aztec

        # Remove old data directory
        DATA_DIR="$HOME/.aztec/alpha-testnet/data"
        [[ -d "$DATA_DIR" ]] && rm -rf "$DATA_DIR"

        echo "Launching Aztec Sequencer Node..."
        ENV_FILE="$HOME/.env.aztec"
        [[ ! -f "$ENV_FILE" ]] && echo "❌ Environment file not found. Run 'Install Aztec Tools' first." && exit 1
        source "$ENV_FILE"

        # Determine host IP
        SERVER_IP=$(hostname -I | awk '{print $1}')

        # Prepare project directory
        PROJECT_DIR="$HOME/aztec"
        mkdir -p "$PROJECT_DIR" && cd "$PROJECT_DIR"

        # Generate docker-compose.yml
        cat > docker-compose.yml <<EOF
services:
  aztec-node:
    container_name: aztec-sequencer
    network_mode: host
    image: aztecprotocol/aztec:alpha-testnet
    restart: unless-stopped
    environment:
      ETHEREUM_HOSTS: $RPC_URL
      L1_CONSENSUS_HOST_URLS: $BEACON_URL
      DATA_DIRECTORY: /data
      VALIDATOR_PRIVATE_KEY: $private_key
      COINBASE: $public_key
      P2P_IP: $SERVER_IP
      LOG_LEVEL: debug
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer'
    volumes:
      - "$HOME/.aztec/alpha-testnet/data/:/data"
EOF

        docker compose up -d
        break
        ;;

      "View Logs")
        docker logs -f aztec-sequencer --tail 100
        break
        ;;

      "Check Sync Status")
        curl -s -X POST -H 'Content-Type: application/json' \
          -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
          http://localhost:8080 | jq -r ".result.proven.number"
        break
        ;;

      "Generate Proof")
        BLOCK_NUMBER=$(curl -s -X POST -H 'Content-Type: application/json' \
          -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
          http://localhost:8080 | jq -r ".result.proven.number")
        echo "Block number: $BLOCK_NUMBER"
        PROOF=$(curl -s -X POST -H 'Content-Type: application/json' \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK_NUMBER\",\"$BLOCK_NUMBER\"],\"id\":67}" \
          http://localhost:8080 | jq -r ".result")
        echo "Proof: $PROOF"
        break
        ;;

      "Update Node")
        docker compose down
        "$HOME/.aztec/bin/aztec-up" alpha-testnet
        rm -rf "$HOME/.aztec/alpha-testnet/data/"
        docker compose up -d
        break
        ;;

      "Uninstall Node")
        read -rp "Wipe all data and remove the Aztec project directory? [y/N] " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
          docker compose down -v
          rm -rf "$HOME/aztec"
        fi
        break
        ;;

      "Exit")
        exit 0
        ;;

      *)
        echo "Invalid option."
        ;;
    esac
  done

done
