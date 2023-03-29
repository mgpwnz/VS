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

sudo apt update && sudo apt install curl -y < "/dev/null"
bash_profile=$HOME/.bash_profile
if [ -f "$bash_profile" ]; then
    . $HOME/.bash_profile
fi
#Logo
sleep 1 && curl -s https://raw.githubusercontent.com/mgpwnz/VS/main/logocz.sh | bash && sleep 2
#var
if [ ! $DEFUND_NODENAME ]; then
read -p "Enter node name: " DEFUND_NODENAME
echo 'export DEFUND_NODENAME='\"${DEFUND_NODENAME}\" >> $HOME/.bash_profile
fi
echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
. $HOME/.bash_profile
sleep 1
cd $HOME
#update
sudo apt update
sudo apt install make clang pkg-config libssl-dev build-essential git jq ncdu bsdmainutils htop -y < "/dev/null"
cd $HOME
#clone go
wget -O go1.19.1.linux-amd64.tar.gz https://golang.org/dl/go1.19.1.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.19.1.linux-amd64.tar.gz && rm go1.19.1.linux-amd64.tar.gz
echo 'export GOROOT=/usr/local/go' >> $HOME/.bash_profile
echo 'export GOPATH=$HOME/go' >> $HOME/.bash_profile
echo 'export GO111MODULE=on' >> $HOME/.bash_profile
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile && . $HOME/.bash_profile
go version
#install
rm -rf $HOME/defund
git clone https://github.com/defund-labs/defund
cd defund
git checkout v0.2.6
make build
sudo mv ./build/defundd /usr/local/bin/ || exit

defundd init "$DEFUND_NODENAME" --chain-id=orbit-alpha-1

seeds="f902d7562b7687000334369c491654e176afd26d@170.187.157.19:26656,2b76e96658f5e5a5130bc96d63f016073579b72d@rpc-1.defund.nodes.guru:45656"
#peers="d9184a3a61c56b803c7b317cd595e83bbae3925e@194.163.174.231:26677,5e7853ec4f74dba1d3ae721ff9f50926107efc38@65.108.6.45:60556,f114c02efc5aa7ee3ee6733d806a1fae2fbfb66b@65.108.46.123:56656,aa2c9df37e372c7928435075497fb0fb7ff9427e@38.129.16.18:26656,f2985029a48319330b99767d676412383e7061bf@194.163.155.84:36656,daff7b8cbcae4902c3c4542113ba521f968cc3f8@213.239.217.52:29656"

sed -i.default "s/^seeds *=.*/seeds = \"$seeds\"/;" $HOME/.defund/config/config.toml
#sed -i "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/;" $HOME/.defund/config/config.toml
sed -i.default -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.0025ufetf\"/" $HOME/.defund/config/app.toml
sed -i "s/pruning *=.*/pruning = \"custom\"/g" $HOME/.defund/config/app.toml
sed -i "s/pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/g" $HOME/.defund/config/app.toml
sed -i "s/pruning-interval *=.*/pruning-interval = \"10\"/g" $HOME/.defund/config/app.toml
#sed -i "s/snapshot-interval *=.*/snapshot-interval = 0/g" $HOME/.defund/config/app.toml
#sed -i.bak -e "s/indexer *=.*/indexer = \"null\"/g" $HOME/.defund/config/config.toml
bash $HOME/defund/devtools/optimize.sh
wget -O $HOME/.defund/config/genesis.json https://raw.githubusercontent.com/defund-labs/testnet/main/orbit-alpha-1/genesis.json
defundd tendermint unsafe-reset-all
#wget -O $HOME/.defund/config/addrbook.json https://api.nodes.guru/defund_addrbook.json

#service
echo "[Unit]
Description=DeFund Node
After=network.target

[Service]
User=$USER
Type=simple
ExecStart=/usr/local/bin/defundd start
Restart=on-failure
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target" > $HOME/defund.service
sudo mv $HOME/defund.service /etc/systemd/system
sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF
echo -e '\n\e[42mRunning a service\e[0m\n' && sleep 1
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
sudo systemctl enable defund
sudo systemctl restart defund
echo -e '\n\e[42mCheck node status\e[0m\n' && sleep 1
if [[ `service defund status | grep active` =~ "running" ]]; then
  echo -e "Your Defund node \e[32minstalled and works\e[39m!"
  echo -e "You can check node status by the command \e[7mservice defund status\e[0m"
  echo -e "Press \e[7mQ\e[0m for exit from status menu"
else
  echo -e "Your Defund node \e[31mwas not installed correctly\e[39m, please reinstall."
fi

}

uninstall(){
sudo systemctl stop defund
sudo systemctl disable defund
rm -rf $HOME/defund
sudo rm -rf /etc/systemd/system/defund.service
sudo rm -rf /usr/local/bin/defund
sudo rm -rf /usr/local/bin/defun

}
# Actions
sudo apt install wget -y &>/dev/null
cd
$function
