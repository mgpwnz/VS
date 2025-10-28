#!/bin/bash
version="2.0.4"

SERVER_IP=$(wget -qO- eth0.me)

# === ФУНКЦІЯ СТВОРЕННЯ DOCKER-COMPOSE ===
container() {
    if [[ "$use_multivalidator" == "true" ]]; then
        # З'єднуємо приватні ключі через кому
        PRIVATE_KEYS_JOINED=$(IFS=,; echo "${private_keys[*]}")
        COINBASE_KEY=${coinbase_key}
        PRIVATE_KEY_FIELD="VALIDATOR_PRIVATE_KEYS: ${PRIVATE_KEYS_JOINED}"
    else
        PRIVATE_KEYS_JOINED=$private_key
        COINBASE_KEY=$public_key
        PRIVATE_KEY_FIELD="VALIDATOR_PRIVATE_KEY: ${private_key}"
    fi

    cat > "$HOME/aztec/docker-compose.yml" <<EOF
services:
  aztec-node:
    container_name: aztec-sequencer
    image: ${image_version}
    restart: unless-stopped
    environment:
      ETHEREUM_HOSTS: ${RPC_URL}
      L1_CONSENSUS_HOST_URLS: ${BEACON_URL}
      DATA_DIRECTORY: /data
      ${PRIVATE_KEY_FIELD}
      COINBASE: ${COINBASE_KEY}
      P2P_IP: ${SERVER_IP}
      LOG_LEVEL: info
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network testnet --node --archiver --sequencer --snapshots-url https://snapshots.aztec.graphops.xyz/files/'
    ports:
      - "40400:40400/tcp"
      - "40400:40400/udp"
      - "8080:8080"
      - "8880:8880"
    volumes:
      - "$HOME/.aztec/alpha-testnet/data/:/data"
EOF
}

# === МЕНЮ ===
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
        # === INSTALL DEPENDENCIES ===
        "Install dependencies")
            echo "Updating packages and installing dependencies..."
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
                autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
                bsdmainutils ncdu unzip
            . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
            break
            ;;

        # === INSTALL AZTEC TOOLS ===
        "Install Aztec Tools")
            echo "Installing Aztec CLI..."
            curl -sL https://install.aztec.network | bash || { echo "❌ Aztec installation failed"; exit 1; }

            AZTEC_DIR="$HOME/.aztec/bin"
            if ! grep -Fxq "export PATH=\"\\$PATH:$AZTEC_DIR\"" "$HOME/.bashrc"; then
                echo "export PATH=\"\\$PATH:$AZTEC_DIR\"" >> "$HOME/.bashrc"
            fi
            echo "✅ Aztec CLI added to PATH. Run: source ~/.bashrc"

            ENV_FILE="$HOME/.env.aztec"
            [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

            if [[ -z "$RPC_URL" ]]; then
                read -p "Enter Sepolia RPC URL: " RPC_URL
                echo "RPC_URL=\"$RPC_URL\"" >> "$ENV_FILE"
            fi
            if [[ -z "$BEACON_URL" ]]; then
                read -p "Enter Beacon node URL: " BEACON_URL
                echo "BEACON_URL=\"$BEACON_URL\"" >> "$ENV_FILE"
            fi

            # === MULTI-VALIDATOR MODE ===
            read -p "Use multi-validator mode? (y/N): " multi_choice
            if [[ "$multi_choice" =~ ^[Yy]$ ]]; then
                echo "use_multivalidator=true" >> "$ENV_FILE"
                read -p "Enter number of validator keys: " key_count
                declare -a private_keys=()
                declare -a public_keys=()
                for ((i=1; i<=key_count; i++)); do
                    read -p "Enter private key #$i: " pk
                    [[ "$pk" != 0x* ]] && pk="0x$pk"
                    private_keys+=("$pk")
                    read -p "Enter public key (EVM address) #$i: " pub
                    public_keys+=("$pub")
                done

                echo
                echo "Select which public key will be used as default COINBASE:"
                for i in "${!public_keys[@]}"; do
                    echo "$((i+1)). ${public_keys[$i]}"
                done
                read -p "Enter number [1-${#public_keys[@]}]: " choice
                COINBASE_KEY=${public_keys[$((choice-1))]}

                {
                    echo "private_keys=(${private_keys[*]})"
                    echo "public_keys=(${public_keys[*]})"
                    echo "coinbase_key=\"$COINBASE_KEY\""
                } >> "$ENV_FILE"
            else
                echo "use_multivalidator=false" >> "$ENV_FILE"
                read -p "Enter your validator private key: " private_key
                [[ "$private_key" != 0x* ]] && private_key="0x$private_key"
                echo "private_key=\"$private_key\"" >> "$ENV_FILE"
                read -p "Enter your EVM address (public key): " public_key
                echo "public_key=\"$public_key\"" >> "$ENV_FILE"
            fi
            break
            ;;

        # === RUN NODE ===
        "Run Sequencer Node")
            CONTAINERS=$(docker ps -q --filter "name=aztec-sequencer")
            if [[ -n "$CONTAINERS" ]]; then
                echo "Stopping running containers..."
                docker stop $CONTAINERS && docker rm $CONTAINERS
            fi

            DATA_DIR="$HOME/.aztec/alpha-testnet/data"
            [[ -d "$DATA_DIR" ]] && rm -rf "$DATA_DIR"

            ENV_FILE="$HOME/.env.aztec"
            if [[ ! -f "$ENV_FILE" ]]; then
                echo "❌ Environment file not found. Please run 'Install Aztec Tools' first."
                exit 1
            fi
            source "$ENV_FILE"

            "$HOME/.aztec/bin/aztec-up" "$version"

            PROJECT_DIR="$HOME/aztec"
            mkdir -p "$PROJECT_DIR"
            cd "$PROJECT_DIR" || exit 1

            read -rp "Enter the image version (default: aztecprotocol/aztec:$version): " image_version
            image_version=${image_version:-aztecprotocol/aztec:"$version"}

            container
            echo "🚀 Starting Aztec Sequencer Node..."
            docker compose up -d
            break
            ;;

        # === VIEW LOGS ===
        "View Logs")
            docker logs -f aztec-sequencer --tail 100
            break
            ;;

        # === CHECK SYNC ===
        "Check Sync Status")
            curl -s -X POST -H 'Content-Type: application/json' \
                -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
                http://localhost:8080 | jq -r ".result.proven.number"
            break
            ;;

        # === UPDATE NODE ===
        "Update Node")
            PROJECT_DIR="$HOME/aztec"
            ENV_FILE="$HOME/.env.aztec"
            [[ ! -f "$ENV_FILE" ]] && { echo "❌ .env.aztec not found"; exit 1; }
            source "$ENV_FILE"

            read -rp "Enter the new version (default: $version): " new_version
            new_version=${new_version:-$version}
            image_version="aztecprotocol/aztec:$new_version"
            "$HOME/.aztec/bin/aztec-up" "$new_version"

            docker image pull "$image_version"
            docker compose -f "$HOME/aztec/docker-compose.yml" down || true
            rm -rf "$HOME/.aztec/alpha-testnet/data/"

            cd "$PROJECT_DIR" || exit 1
            container
            docker compose up -d
            echo "✅ Node updated to $new_version"
            break
            ;;

        # === UNINSTALL NODE ===
        "Uninstall Node")
            read -rp "Wipe all data and remove the Aztec project directory? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                docker compose -f "$HOME/aztec/docker-compose.yml" down -v
                rm -rf "$HOME/aztec"
                echo "✅ Aztec Sequencer Node and data removed."
            fi
            break
            ;;

        # === EXIT ===
        "Exit")
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
        esac
    done
done
