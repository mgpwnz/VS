#!/bin/bash
version="2.0.3"
SERVER_IP=$(wget -qO- eth0.me)

prepare_directories() {
    PROJECT_DIR="$HOME/aztec"
    KEY_DIR="$PROJECT_DIR/keys"
    DATA_DIR="$PROJECT_DIR/data"

    mkdir -p "$KEY_DIR" "$DATA_DIR"

    ENV_FILE="$PROJECT_DIR/.env"
    if [[ -f "$ENV_FILE" ]]; then
        echo ".env file already exists at $ENV_FILE"
        read -p "Overwrite? [y/N]: " resp
        [[ ! "$resp" =~ ^[Yy]$ ]] && return
    fi

    read -p "Enter L1 execution endpoint(s) (comma separated): " RPC_URL
    read -p "Enter L1 consensus endpoint(s) (comma separated): " BEACON_URL

    cat > "$ENV_FILE" <<EOF
DATA_DIRECTORY=./data
KEY_STORE_DIRECTORY=./keys
LOG_LEVEL=info
ETHEREUM_HOSTS=$RPC_URL
L1_CONSENSUS_HOST_URLS=$BEACON_URL
P2P_IP=$SERVER_IP
P2P_PORT=40400
AZTEC_PORT=8080
AZTEC_ADMIN_PORT=8880
EOF

    echo "✅ Directories and .env prepared."
}

generate_keystore() {
    KEY_DIR="$HOME/aztec/keys"
    mkdir -p "$KEY_DIR"

    existing=$(ls "$KEY_DIR"/*.json 2>/dev/null)
    if [[ -n "$existing" ]]; then
        echo "Existing keystore files:"
        ls -1 "$KEY_DIR"/*.json
        read -p "Add new keystore or overwrite? [add/overwrite/skip]: " resp
        case $resp in
        overwrite)
            rm -f "$KEY_DIR"/*.json
            ;;
        skip)
            return
            ;;
        esac
    fi

    while true; do
        echo "Select keystore type:"
        select opt in "Single keystore" "Multiple sequencers" "Done"; do
            case $opt in
            "Single keystore")
                read -p "Enter attester (private key): " attester
                [[ "$attester" != 0x* ]] && attester="0x$attester"
                read -p "Enter fee recipient (EVM address): " feeRecipient
                cat > "$KEY_DIR/keystore.json" <<EOF
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
                echo "✅ Created $KEY_DIR/keystore.json"
                break
                ;;
            "Multiple sequencers")
                while true; do
                    read -p "Enter sequencer ID (e.g., a/b/c): " name
                    read -p "Enter attester (private key): " attester
                    [[ "$attester" != 0x* ]] && attester="0x$attester"
                    read -p "Enter fee recipient address: " feeRecipient
                    cat > "$KEY_DIR/keystore-sequencer-${name}.json" <<EOF
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
                    echo "✅ Created $KEY_DIR/keystore-sequencer-${name}.json"
                    read -p "Add another sequencer? (y/n): " cont
                    [[ "$cont" =~ ^[Nn]$ ]] && break
                done
                break
                ;;
            "Done")
                return
                ;;
            *)
                echo "Invalid option."
                ;;
            esac
        done
    done
}

generate_docker_compose() {
    PROJECT_DIR="$HOME/aztec"
    source "$PROJECT_DIR/.env"

    read -rp "Enter Docker image version (default: aztecprotocol/aztec:$version): " image_version
    image_version=${image_version:-aztecprotocol/aztec:$version}

    cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
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
}

run_node() {
    PROJECT_DIR="$HOME/aztec"
    cd "$PROJECT_DIR" || { echo "Cannot enter project directory"; exit 1; }

    docker compose down || true
    docker compose up -d
    echo "✅ Aztec Sequencer Node is running"
}

# Menu
PS3='Select an action: '
options=(
    "Install dependencies"
    "Prepare directories + .env"
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
        "Install dependencies")
            echo "Updating system and installing packages..."
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y curl iptables build-essential git wget lz4 jq make gcc nano automake \
                autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang \
                bsdmainutils ncdu unzip
            . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
            break
            ;;
        "Prepare directories + .env")
            prepare_directories
            break
            ;;
        "Generate keystore(s)")
            generate_keystore
            break
            ;;
        "Run Sequencer Node")
            prepare_directories
            generate_keystore
            generate_docker_compose
            run_node
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
        "Update Node")
            read -rp "Enter new image version: " new_version
            PROJECT_DIR="$HOME/aztec"
            cd "$PROJECT_DIR" || exit
            docker compose down || true
            docker pull "aztecprotocol/aztec:$new_version"
            generate_docker_compose
            run_node
            break
            ;;
        "Uninstall Node")
            read -rp "Wipe all data and remove Aztec project directory? [y/N] " resp
            [[ "$resp" =~ ^[Yy]$ ]] && rm -rf "$HOME/aztec"
            docker compose down || true
            echo "✅ Aztec Sequencer Node removed"
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
