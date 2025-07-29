#!/bin/bash
# Aztec Sequencer Node Management Script
# This script allows you to install system dependencies, Aztec CLI tools,
# run & manage the Aztec Sequencer Node, view logs, check sync status, update, or uninstall.
version="1.2.0"
container() {
    # Generate docker-compose.yml with actual values
            cat > docker-compose.yml <<EOF
services:
  aztec-node:
    container_name: aztec-sequencer
    image: "$image_version"
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
    ports:
      - "40400:40400/tcp"
      - "40400:40400/udp"
      - "8080:8080"
    volumes:
      - "$HOME/.aztec/alpha-testnet/data/:/data"
EOF
}
PS3='Select an action: '
options=(
    "Install dependencies"
    "Install Aztec Tools"
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
        "Install dependencies")
            echo "Updating package lists and installing required packages..."
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
                autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
                bsdmainutils ncdu unzip
            # Install Docker if not already present
            . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
            break
            ;;

        "Install Aztec Tools")
            echo "Installing Aztec CLI..."
            curl -sL https://install.aztec.network | bash || { echo "❌ Aztec installation failed"; exit 1; }

            # Add Aztec CLI to PATH in .bashrc if not already present
            AZTEC_DIR="$HOME/.aztec/bin"
            if ! grep -Fxq "export PATH=\"\\$PATH:$AZTEC_DIR\"" "$HOME/.bashrc"; then
                echo "export PATH=\"\\$PATH:$AZTEC_DIR\"" >> "$HOME/.bashrc"
            fi
            echo "✅ Aztec CLI added to PATH. To apply changes, type: source ~/.bashrc or restart terminal."

            # Create or source environment file
            ENV_FILE="$HOME/.env.aztec"
            [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

            # Prompt for required variables if missing
            if [[ -z "$RPC_URL" ]]; then
                read -p "Enter Sepolia RPC URL: " RPC_URL
                echo "RPC_URL=\"$RPC_URL\"" >> "$ENV_FILE"
            fi
            if [[ -z "$BEACON_URL" ]]; then
                read -p "Enter Beacon node URL: " BEACON_URL
                echo "BEACON_URL=\"$BEACON_URL\"" >> "$ENV_FILE"
            fi
            if [[ -z "$private_key" ]]; then
                read -p "Enter your validator private key: " private_key
                # Ensure private key starts with 0x
                if [[ "$private_key" != 0x* ]]; then
                    private_key="0x$private_key"
                fi
                echo "private_key=\"$private_key\"" >> "$ENV_FILE"
            fi
            if [[ -z "$public_key" ]]; then
                read -p "Enter your EVM address (public key): " public_key
                echo "public_key=\"$public_key\"" >> "$ENV_FILE"
            fi
            break
            ;;

        "Run Sequencer Node")
            # echo "Finding and cleaning up existing Aztec Sequencer Node..."
            # # Kill tmux session if exists
            # if tmux has-session -t aztec 2>/dev/null; then
            #     echo "Killing tmux session 'aztec'..."
            #     tmux kill-session -t aztec
            # else
            #     echo "No tmux session 'aztec' found."
            # fi
            # Stop and remove containers if any
            CONTAINERS=$(docker ps -q --filter "name=aztec-start")
            if [[ -n "$CONTAINERS" ]]; then
                echo "Stopping Aztec sequencer containers..."
                docker stop $CONTAINERS && docker rm $CONTAINERS
            else
                echo "No running Aztec sequencer containers found."
            fi
            # Delete old data if present
            DATA_DIR="$HOME/.aztec/alpha-testnet/data"
            if [[ -d "$DATA_DIR" ]]; then
                echo "Removing old data directory..."
                rm -rf "$DATA_DIR"
            else
                echo "Data directory not found at $DATA_DIR."
            fi
            echo "Preparing to launch the Aztec Sequencer Node..."
            ENV_FILE="$HOME/.env.aztec"
            if [[ ! -f "$ENV_FILE" ]]; then
                echo "❌ Environment file not found. Please run 'Install Aztec Tools' first."; exit 1
            fi
            source "$ENV_FILE"
            # Update CLI tools
            "$HOME/.aztec/bin/aztec-up" "$version"
            # Determine the server's primary IP
            SERVER_IP=$(wget -qO- icanhazip.com)

            # Create and navigate to the project directory
            PROJECT_DIR="$HOME/aztec"
            mkdir -p "$PROJECT_DIR"
            cd "$PROJECT_DIR" || { echo "❌ Cannot change to project directory"; exit 1; }
            # Prompt for image version with correct fallback
            read -rp "Enter the image version (default: aztecprotocol/aztec:"$version"): " image_version
            image_version=${image_version:-aztecprotocol/aztec:"$version"}
            # Generate docker-compose.yml with actual values
            container
            echo "Starting Aztec Sequencer Node..."
            # Start the node
            docker compose up -d
            break
            ;;

        "View Logs")
            echo "Tailing the last 100 lines of Aztec Sequencer logs..."
            docker logs -f aztec-sequencer --tail 100
            break
            ;;

        "Check Sync Status")
            echo "Fetching L2 tip number from the local Sequencer RPC..."
            curl -s -X POST -H 'Content-Type: application/json' \
                -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
                http://localhost:8080 | jq -r ".result.proven.number"
            break
            ;;
        "Generate Proof")
            echo "Generating proof..."
            # Check block number
            BLOCK_NUMBER=$(curl -s -X POST -H 'Content-Type: application/json' \
                -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
                http://localhost:8080 | jq -r ".result.proven.number")
            echo "Block number: $BLOCK_NUMBER"
            # Generate proof using actual block number
            PROOF=$(curl -s -X POST -H 'Content-Type: application/json' \
                -d "{\"jsonrpc\":\"2.0\",\"method\":\"node_getArchiveSiblingPath\",\"params\":[\"$BLOCK_NUMBER\",\"$BLOCK_NUMBER\"],\"id\":67}" \
                http://localhost:8080 | jq -r ".result")
            echo "Proof: $PROOF"
            break
            ;;
        "Update Node")
            ENV_FILE="$HOME/.env.aztec"
            if [[ ! -f "$ENV_FILE" ]]; then
                echo "❌ Environment file not found. Please run 'Install Aztec Tools' first."; exit 1
            fi
            source "$ENV_FILE"
            read -rp "Enter the new version (default: $version): " new_version
            new_version=${new_version:-$version}

            echo "Updating Aztec Sequencer Node to version $new_version..."
            docker image pull aztecprotocol/aztec:"$new_version"
            docker compose -f "$HOME/aztec/docker-compose.yml" down
            "$HOME/.aztec/bin/aztec-up" "$new_version"
            rm -rf "$HOME/.aztec/alpha-testnet/data/"
            # Recreate the docker-compose.yml with the new version
            rm -f "$HOME/aztec/docker-compose.yml"
            sleep 10
            container
            echo "Restarting the Aztec Sequencer Node with the new version..."
            docker compose -f "$HOME/aztec/docker-compose.yml" up -d
            break
            ;;


        "Uninstall Node")
            read -rp "Wipe all data and remove the Aztec project directory? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                docker compose -f "$HOME/aztec/docker-compose.yml" down -v
                rm -rf "$HOME/aztec"
                echo "Aztec Sequencer Node and data removed."
            else
                echo "Uninstallation cancelled."
            fi
            break
            ;;

        "Exit")
            echo "Goodbye!"; exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
        esac
    done

done
