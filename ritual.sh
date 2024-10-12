#!/bin/bash
# Default variables
function="install"
REGISTRY_ADDRESS=0x3B1554f346DFe5c482Bb4BA31b880c1C18412170
RPC=https://mainnet.base.org/
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -up|--update)
            function="update"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        *|--)
    break
	;;
	esac
done
install() {
#pre
function check_empty {
  local varname=$1
  while [ -z "${!varname}" ]; do
    read -p "$2" input
    if [ -n "$input" ]; then
      eval $varname=\"$input\"
    else
      echo "The value cannot be empty. Please try again."
    fi
  done
}

function confirm_input {
  echo "You have entered the following information:"
  echo Private Key: "$PRIVATE_KEY"
  read -p "Is this information correct? (yes/no): " CONFIRM
  CONFIRM=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
  
  if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "y" ]; then
    echo "Let's try again..."
    return 1 
  fi
  return 0 
}

while true; do
  PRIVATE_KEY=""

  check_empty PRIVATE_KEY "Enter private key: "
  
  confirm_input
  if [ $? -eq 0 ]; then
    break 
  fi
done

echo "All data is confirmed. Proceeding..."
#upd    
sudo apt update -y
sudo apt install mc wget curl git htop netcat net-tools unzip jq build-essential ncdu tmux make cmake clang pkg-config libssl-dev protobuf-compiler bc lz4 screen -y
#iptables Redis
sudo apt-get install iptables-persistent -y
sudo iptables -A INPUT -p tcp --dport 6379 -j DROP
sudo netfilter-persistent save

#docker install
cd $HOME
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
#clone
git clone https://github.com/ritual-net/infernet-container-starter
cd infernet-container-starter
cp projects/hello-world/container/config.json deploy/config.json
#change config
DEPLOY_JSON=deploy/config.json
sed -i "s|\"rpc_url\": \"[^\"]*\"|\"rpc_url\": \"$RPC\"|" "$DEPLOY_JSON"
sed -i "s|\"private_key\": \"[^\"]*\"|\"private_key\": \"$PRIVATE_KEY\"|" "$DEPLOY_JSON"
sed -i "s|\"registry_address\": \"[^\"]*\"|\"registry_address\": \"$REGISTRY_ADDRESS\"|" "$DEPLOY_JSON"
sed -i 's|"sleep": 3|"sleep": 5|' "$DEPLOY_JSON"
sed -i 's|"batch_size": 100|"batch_size": 1800, "starting_sub_id": 100000|' "$DEPLOY_JSON"
# Configure container/config.json
CONTAINER_JSON=projects/hello-world/container/config.json
sed -i "s|\"rpc_url\": \"[^\"]*\"|\"rpc_url\": \"$RPC\"|" "$CONTAINER_JSON"
sed -i "s|\"private_key\": \"[^\"]*\"|\"private_key\": \"$PRIVATE_KEY\"|" "$CONTAINER_JSON"
sed -i "s|\"registry_address\": \"[^\"]*\"|\"registry_address\": \"$REGISTRY_ADDRESS\"|" "$CONTAINER_JSON"
sed -i 's|"sleep": 3|"sleep": 5|' "$CONTAINER_JSON"
sed -i 's|"batch_size": 100|"batch_size": 1800, "starting_sub_id": 100000|' "$CONTAINER_JSON"
# Update contract script
sed -i "s|address registry = .*|address registry = $REGISTRY_ADDRESS;|" projects/hello-world/contracts/script/Deploy.s.sol
# Configure Makefile
MAKEFILE=projects/hello-world/contracts/Makefile
sed -i "s|sender := .*|sender := $PRIVATE_KEY|" "$MAKEFILE"
sed -i "s|RPC_URL := .*|RPC_URL := $RPC|" "$MAKEFILE"
# Start containers
sed -i 's|ritualnetwork/infernet-node:1.0.0|ritualnetwork/infernet-node:1.2.0|' deploy/docker-compose.yaml
sed -i 's|0.0.0.0:4000:4000|0.0.0.0:4321:4000|' deploy/docker-compose.yaml
sed -i 's|8545:3000|8845:3000|' deploy/docker-compose.yaml
sed -i 's|container_name: infernet-anvil|container_name: infernet-anvil\n    restart: on-failure|' deploy/docker-compose.yaml

docker compose -f deploy/docker-compose.yaml up -d
# Install Foundry
cd "$HOME"
mkdir -p foundry
cd foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
echo 'export PATH="$PATH:/root/.foundry/bin"' >> .profile
source .profile
foundryup

# Install contract dependencies
cd "$HOME/infernet-container-starter/projects/hello-world/contracts/lib/"
rm -r forge-std infernet-sdk
forge install --no-commit foundry-rs/forge-std
forge install --no-commit ritual-net/infernet-sdk

# Deploy consumer contract
cd "$HOME/infernet-container-starter"
project=hello-world make deploy-contracts >> logs.txt
CONTRACT_ADDRESS=$(grep "Deployed SaysHello" logs.txt | awk '{print $NF}')
rm -rf logs.txt
if [ -z "$CONTRACT_ADDRESS" ]; then
    echo "Error: cant read contractAddress"
    exit 1
fi

echo "Contract address: $CONTRACT_ADDRESS"
sed -i "s|0x13D69Cf7d6CE4218F646B759Dcf334D82c023d8e|$CONTRACT_ADDRESS|" "$HOME/infernet-container-starter/projects/hello-world/contracts/script/CallContract.s.sol"

# Call consumer contract
cd "$HOME/infernet-container-starter"
project=hello-world make call-contract

# Restart Docker containers
cd "$HOME/infernet-container-starter/deploy"
docker compose down
sleep 3
sudo rm -rf docker-compose.yaml
FILE="docker-compose.yaml"
cat <<EOF > $FILE
services:
  node:
    image: ritualnetwork/infernet-node:1.2.0
    ports:
      - "0.0.0.0:4100:4000"
    volumes:
      - ./config.json:/app/config.json
      - node-logs:/logs
      - /var/run/docker.sock:/var/run/docker.sock
    tty: true
    networks:
      - network
    depends_on:
      - redis
    restart:
      on-failure
    extra_hosts:
      - "host.docker.internal:host-gateway"
    stop_grace_period: 1m
    container_name: infernet-node

  redis:
    image: redis:7.4.0
    ports:
    - "6379:6379"
    networks:
      - network
    volumes:
      - ./redis.conf:/usr/local/etc/redis/redis.conf
      - redis-data:/data
    restart:
      on-failure

  fluentbit:
    image: fluent/fluent-bit:3.1.4
    expose:
      - "24224"
    environment:
      - FLUENTBIT_CONFIG_PATH=/fluent-bit/etc/fluent-bit.conf
    volumes:
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
      - /var/log:/var/log:ro
    networks:
      - network
    restart:
      on-failure

networks:
  network:

volumes:
  node-logs:
  redis-data:
EOF

docker compose up -d
docker rm -fv infernet-anvil &>/dev/null

}

uninstall() {
if [ ! -d "$HOME/infernet-container-starter" ]; then
    echo "Directory not found"
    break
fi

read -r -p "Wipe all DATA? [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY]) 
        docker-compose -f "$HOME/infernet-container-starter/docker-compose.yml" down -v
        rm -rf "$HOME/infernet-container-starter"
        echo "Data wiped"
        ;;
    *)
        echo "Canceled"
        break
        ;;
esac
}
# Actions
sudo apt install wget -y &>/dev/null
cd
$function