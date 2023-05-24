#!/bin/bash

while true
do


# Menu

PS3='Select an action: '
options=("Install" "Change ipv4 to ipv6" "Auto buy rolls" "Add to stake" "Discord register" "Contabo add ipv6" "Wallet info" "Exit")
select opt in "${options[@]}"
               do
                   case $opt in                           

"Install")
echo "============================================================"
echo "Install start"
echo "============================================================"

if [ -d $HOME/massa/ ]; then
		. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/massa_update.sh)
	else 
        if [ ! -n "$massa_password" ]; then
		echo Create password and save it in the variable!
		read -p "Enter passwd: " massa_password
		echo 'export massa_password='${massa_password} >> $HOME/.bash_profile
	    fi
		sudo apt update
		sudo apt upgrade -y
		sudo apt install jq curl pkg-config git build-essential libssl-dev -y
		massa_version=`wget -qO- https://api.github.com/repos/massalabs/massa/releases/latest | jq -r ".tag_name"`
		wget -qO $HOME/massa.tar.gz "https://github.com/massalabs/massa/releases/download/${massa_version}/massa_${massa_version}_release_linux.tar.gz"
		if [ `wc -c < "$HOME/massa.tar.gz"` -ge 1000 ]; then
			tar -xvf $HOME/massa.tar.gz
			rm -rf $HOME/massa.tar.gz
			chmod +x $HOME/massa/massa-node/massa-node $HOME/massa/massa-client/massa-client
			sudo tee <<EOF >/dev/null /etc/systemd/system/massad.service
[Unit]
Description=Massa Node
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$HOME/massa/massa-node
ExecStart=$HOME/massa/massa-node/massa-node -p "$massa_password"
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
			sudo systemctl enable massad
			sudo systemctl daemon-reload
			cd $HOME/massa/massa-client/
			if [ ! -d $HOME/massa_backup ]; then
				./massa-client -p "$massa_password" wallet_generate_secret_key &>/dev/null
				mkdir -p $HOME/massa_backup
				sudo cp $HOME/massa/massa-client/wallet.dat $HOME/massa_backup/wallet.dat
				while true; do
					if [ -f $HOME/massa/massa-node/config/node_privkey.key ]; then
						sudo cp $HOME/massa/massa-node/config/node_privkey.key $HOME/massa_backup/node_privkey.key
						break
					else
						sleep 5
					fi
				done
				
			else
				sudo cp $HOME/massa_backup/node_privkey.key $HOME/massa/massa-node/config/node_privkey.key
				sudo systemctl restart massad
				sudo cp $HOME/massa_backup/wallet.dat $HOME/massa/massa-client/wallet.dat	
			fi
			
			cd
			
		else
			rm -rf $HOME/massa.tar.gz
			echo Archive with binary downloaded unsuccessfully!
		fi
	fi
echo Done!
break
;;

"Change ipv4 to ipv6")
#old script
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/massa_add.sh)
break
;;
"Auto buy rolls")
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/massa_add.sh) -ab
break
;;
"Add to stake")
node_start_staking() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local resp=`./massa-client -p "$massa_password" node_start_staking "$address"`
	if grep -q "error" <<< "$resp"; then
		echo Failed to register a key for staking!
	else
		echo Done!
	fi
}
break
;;
"Discord register")
node_testnet_rewards_program_ownership_proof() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local discord_id
	echo Enter a Discord ID:
	read -r discord_id
	local resp=`./massa-client -p "$massa_password" -j node_testnet_rewards_program_ownership_proof "$main_address" "$discord_id" | jq -r`
	echo "$resp"
}
break
;;
"Contabo add ipv6")
. <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/massa_add.sh) -cb
break
;;
"Wallet info")
wallet_info() {
	local wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
}
break
;;
"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done