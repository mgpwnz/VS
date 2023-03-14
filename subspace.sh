#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -sc|--second)
            function="second"
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
#docker install
cd
if ! docker --version; then
		echo -e "${C_LGn}Docker installation...${RES}"
		sudo apt update
		sudo apt upgrade -y
		sudo apt install curl apt-transport-https ca-certificates gnupg lsb-release -y
		. /etc/*-release
		wget -qO- "https://download.docker.com/linux/${DISTRIB_ID,,}/gpg" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
		echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt update
		sudo apt install docker-ce docker-ce-cli containerd.io -y
		docker_version=`apt-cache madison docker-ce | grep -oPm1 "(?<=docker-ce \| )([^_]+)(?= \| https)"`
		sudo apt install docker-ce="$docker_version" docker-ce-cli="$docker_version" containerd.io -y
	fi
	if ! docker-compose --version; then
		echo -e "${C_LGn}Docker Сompose installation...${RES}"
		sudo apt update
		sudo apt upgrade -y
		sudo apt install wget jq -y
		local docker_compose_version=`wget -qO- https://api.github.com/repos/docker/compose/releases/latest | jq -r ".tag_name"`
		sudo wget -O /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-`uname -s`-`uname -m`"
		sudo chmod +x /usr/bin/docker-compose
		. $HOME/.bash_profile
	fi
cd $HOME
#create var
#SUBSPACE_WALLET_ADDRESS
if [ ! $SUBSPACE_WALLET_ADDRESS ]; then
		read -p "Enter wallet address: " SUBSPACE_WALLET_ADDRESS
		echo 'export SUBSPACE_WALLET_ADDRESS='${SUBSPACE_WALLET_ADDRESS} >> $HOME/.bash_profile
	fi
#SUBSPACE_NODE_NAME
if [ ! $SUBSPACE_NODE_NAME ]; then
		read -p "Enter node name: " SUBSPACE_NODE_NAME
		echo 'export SUBSPACE_NODE_NAME='${SUBSPACE_NODE_NAME} >> $HOME/.bash_profile
	fi
#SUBSPACE_PLOT_SIZE
if [ ! $SUBSPACE_PLOT_SIZE ]; then
		read -p "Enter plot size 50-100G: " SUBSPACE_PLOT_SIZE
		echo 'export SUBSPACE_PLOT_SIZE='${SUBSPACE_PLOT_SIZE} >> $HOME/.bash_profile
	fi
#version
local subspace_version=`wget -qO- https://api.github.com/repos/subspace/subspace/releases/latest | jq -r ".tag_name"`
#create dir and config
mkdir $HOME/subspace
cd $HOME/subspace
sleep 1
 # Create script 
 tee $HOME/subspace/docker-compose.yml > /dev/null <<EOF
  version: "3.7"
  services:
    node:
      # For running on Aarch64 add `-aarch64` after `DATE`
      image: ghcr.io/subspace/node:gemini-3c-2023-mar-07
      volumes:
  # Instead of specifying volume (which will store data in `/var/lib/docker`), you can
  # alternatively specify path to the directory where files will be stored, just make
  # sure everyone is allowed to write there
        - node-data:/var/subspace:rw
  #      - /path/to/subspace-node:/var/subspace:rw
      ports:
  # If port 30333 or 30433 is already occupied by another Substrate-based node, replace all
  # occurrences of `30333` or `30433` in this file with another value
        - "0.0.0.0:32333:30333"
        - "0.0.0.0:32433:30433"
      restart: unless-stopped
      command: [
        "--chain", "gemini-3c",
        "--base-path", "/var/subspace",
        "--execution", "wasm",
        "--blocks-pruning", "archive",
        "--state-pruning", "archive",
        "--port", "30333",
        "--dsn-listen-on", "/ip4/0.0.0.0/tcp/30433",
        "--rpc-cors", "all",
        "--rpc-methods", "safe",
        "--unsafe-ws-external",
        "--dsn-disable-private-ips",
        "--no-private-ipv4",
        "--validator",
  # Replace `INSERT_YOUR_ID` with your node ID (will be shown in telemetry)
        "--name", "$SUBSPACE_NODE_NAME"
      ]
      healthcheck:
        timeout: 5s
  # If node setup takes longer than expected, you want to increase `interval` and `retries` number.
        interval: 30s
        retries: 5

    farmer:
      depends_on:
        node:
          condition: service_healthy
      # For running on Aarch64 add `-aarch64` after `DATE`
      image: ghcr.io/subspace/farmer:gemini-3c-2023-mar-07
      volumes:
  # Instead of specifying volume (which will store data in `/var/lib/docker`), you can
  # alternatively specify path to the directory where files will be stored, just make
  # sure everyone is allowed to write there
        - farmer-data:/var/subspace:rw
  #      - /path/to/subspace-farmer:/var/subspace:rw
      ports:
  # If port 30533 is already occupied by something else, replace all
  # occurrences of `30533` in this file with another value
        - "0.0.0.0:32533:30533"
      restart: unless-stopped
      command: [
        "--base-path", "/var/subspace",
        "farm",
        "--disable-private-ips",
        "--node-rpc-url", "ws://node:9944",
        "--listen-on", "/ip4/0.0.0.0/tcp/30533",
  # Replace `WALLET_ADDRESS` with your Polkadot.js wallet address
        "--reward-address", "$SUBSPACE_WALLET_ADDRESS_ADDRESS",
  # Replace `PLOT_SIZE` with plot size in gigabytes or terabytes, for instance 100G or 2T (but leave at least 60G of disk space for node and some for OS)
        "--plot-size", "$SUBSPACE_PLOT_SIZE"
      ]
  volumes:
    node-data:
    farmer-data:
EOF
sleep 2
#docker run
cd $HOME/subspace && docker compose up -d && docker compose logs -f
}
second() {
cd $HOME
#create var2
#SUBSPACE_WALLET_ADDRESS2
if [ ! $SUBSPACE_WALLET_ADDRESS2 ]; then
		read -p "Enter wallet address2: " SUBSPACE_WALLET_ADDRESS2
		echo 'export SUBSPACE_WALLET_ADDRESS2='${SUBSPACE_WALLET_ADDRESS2} >> $HOME/.bash_profile
	fi
#SUBSPACE_NODE_NAME2
if [ ! $SUBSPACE_NODE_NAME2 ]; then
		read -p "Enter node name2: " SUBSPACE_NODE_NAME2
		echo 'export SUBSPACE_NODE_NAME2='${SUBSPACE_NODE_NAME2} >> $HOME/.bash_profile
	fi
#SUBSPACE_PLOT_SIZE
if [ ! $SUBSPACE_PLOT_SIZE2 ]; then
		read -p "Enter plot size 50-100G: " SUBSPACE_PLOT_SIZE2
		echo 'export SUBSPACE_PLOT_SIZE2='${SUBSPACE_PLOT_SIZE2} >> $HOME/.bash_profile
	fi
#version
local subspace_version=`wget -qO- https://api.github.com/repos/subspace/subspace/releases/latest | jq -r ".tag_name"`
#create dir and config
mkdir $HOME/subspace2
cd $HOME/subspace2
sleep 1
 # Create script 
 tee $HOME/subspace2/docker-compose.yml > /dev/null <<EOF
  version: "3.7"
  services:
    node:
      # For running on Aarch64 add `-aarch64` after `DATE`
      image: ghcr.io/subspace/node:gemini-3c-2023-mar-07
      volumes:
  # Instead of specifying volume (which will store data in `/var/lib/docker`), you can
  # alternatively specify path to the directory where files will be stored, just make
  # sure everyone is allowed to write there
        - node-data:/var/subspace:rw
  #      - /path/to/subspace-node:/var/subspace:rw
      ports:
  # If port 30333 or 30433 is already occupied by another Substrate-based node, replace all
  # occurrences of `30333` or `30433` in this file with another value
        - "0.0.0.0:34333:30333"
        - "0.0.0.0:34433:30433"
      restart: unless-stopped
      command: [
        "--chain", "gemini-3c",
        "--base-path", "/var/subspace",
        "--execution", "wasm",
        "--blocks-pruning", "archive",
        "--state-pruning", "archive",
        "--port", "30333",
        "--dsn-listen-on", "/ip4/0.0.0.0/tcp/30433",
        "--rpc-cors", "all",
        "--rpc-methods", "safe",
        "--unsafe-ws-external",
        "--dsn-disable-private-ips",
        "--no-private-ipv4",
        "--validator",
  # Replace `INSERT_YOUR_ID` with your node ID (will be shown in telemetry)
        "--name", "$SUBSPACE_NODE_NAME"
      ]
      healthcheck:
        timeout: 5s
  # If node setup takes longer than expected, you want to increase `interval` and `retries` number.
        interval: 30s
        retries: 5

    farmer:
      depends_on:
        node:
          condition: service_healthy
      # For running on Aarch64 add `-aarch64` after `DATE`
      image: ghcr.io/subspace/farmer:gemini-3c-2023-mar-07
      volumes:
  # Instead of specifying volume (which will store data in `/var/lib/docker`), you can
  # alternatively specify path to the directory where files will be stored, just make
  # sure everyone is allowed to write there
        - farmer-data:/var/subspace:rw
  #      - /path/to/subspace-farmer:/var/subspace:rw
      ports:
  # If port 34533 is already occupied by something else, replace all
  # occurrences of `30533` in this file with another value
        - "0.0.0.0:30533:30533"
      restart: unless-stopped
      command: [
        "--base-path", "/var/subspace",
        "farm",
        "--disable-private-ips",
        "--node-rpc-url", "ws://node:9944",
        "--listen-on", "/ip4/0.0.0.0/tcp/30533",
  # Replace `WALLET_ADDRESS` with your Polkadot.js wallet address
        "--reward-address", "$SUBSPACE_WALLET_ADDRESS_ADDRESS",
  # Replace `PLOT_SIZE` with plot size in gigabytes or terabytes, for instance 100G or 2T (but leave at least 60G of disk space for node and some for OS)
        "--plot-size", "$SUBSPACE_PLOT_SIZE"
      ]
  volumes:
    node-data:
    farmer-data:
EOF
sleep 2
#docker run
cd $HOME/subspace && docker compose up -d && docker compose logs -f


}
uninstall() {
cd $HOME/subspace && docker compose down -v
sudo rm -rf $HOME/subspace 
echo "Done"
}
# Actions
sudo apt install tmux wget -y &>/dev/null
cd
$function