#!/bin/bash
#UPDATE
	if [ ! -n "$massa_password" ]; then
		echo Create password and save it in the variable!
		read -p "Enter passwd: " massa_password
		echo 'export massa_password='${massa_password} >> $HOME/.bash_profile
	fi
	fi
	mkdir -p $HOME/massa_backup
	if [ ! -f $HOME/massa_backup/wallet.dat ]; then
		sudo cp $HOME/massa/massa-client/wallet.dat $HOME/massa_backup/wallet.dat
	fi
	if [ ! -f $HOME/massa_backup/node_privkey.key ]; then
		sudo cp $HOME/massa/massa-node/config/node_privkey.key $HOME/massa_backup/node_privkey.key
	fi
	if grep -q "wrong password" <<< `cd $HOME/massa/massa-client/; ./massa-client -p "$massa_password" 2>&1; cd`; then
		echo Wrong password!
        echo Enter the correct one with the following command and run the script again.
        read -p "Enter passwd: " massa_password
		echo 'export massa_password='${massa_password} >> $HOME/.bash_profile
		return 1 2>/dev/null; exit 1
	fi
	local massa_version=`wget -qO- https://api.github.com/repos/massalabs/massa/releases/latest | jq -r ".tag_name"`
	wget -qO $HOME/massa.tar.gz "https://github.com/massalabs/massa/releases/download/${massa_version}/massa_${massa_version}_release_linux.tar.gz"
	if [ `wc -c < "$HOME/massa.tar.gz"` -ge 1000 ]; then
		rm -rf $HOME/massa/
		tar -xvf $HOME/massa.tar.gz
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
		sudo cp $HOME/massa_backup/node_privkey.key $HOME/massa/massa-node/config/node_privkey.key
		sudo cp $HOME/massa_backup/wallet.dat $HOME/massa/massa-client/wallet.dat
echo Node Updated!

	else
		echo Archive with binary downloaded unsuccessfully!
	fi
	rm -rf $HOME/massa.tar.gz