#!/bin/bash
# Default variables
function="version6"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        v6|--version6)
            function="version6"
            shift
            ;;
        -ab|--autobuy)   
            function="autobuy"
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
# change config
configv6() {
    sudo systemctl stop massad
    ipv6=$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')
    sudo tee <<EOF >/dev/null $HOME/massa/massa-node/config/config.toml
[protocol]
routable_ip = "$ipv6"
EOF
	sudo systemctl restart massad
    . <(wget -qO- https://raw.githubusercontent.com/SecorD0/Massa/main/insert_variables.sh)
}
secret() {
    cd $HOME/massa/massa-client/
    echo Waiting for the node to start
   if [ ! -d $HOME/massa_backup ]; then
				while true; do
					if [ -f $HOME/massa/massa-node/config/node_privkey.key ]; then
						./massa-client -p "$massa_password" wallet_generate_secret_key
						mkdir -p $HOME/massa_backup
						sudo cp $HOME/massa/massa-client/wallet.dat $HOME/massa_backup/wallet.dat
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
}

##########################
#       VER. IPV6        #
##########################
version6() {
if [ -d $HOME/massa/ ]; then
            updatev6
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
            configv6
            secret
            autobuy
            echo The node was started!
            cat $HOME/massa/massa-node/config/config.toml
            else
                rm -rf $HOME/massa.tar.gz
                echo Archive is not downloaded!
            fi
        fi



}
# config ipv6
updatev6() {
            mkdir -p $HOME/massa_backup
            if [ ! -f $HOME/massa_backup/wallet.dat ]; then
		        sudo cp $HOME/massa/massa-client/wallet.dat $HOME/massa_backup/wallet.dat
	        fi
	        if [ ! -f $HOME/massa_backup/node_privkey.key ]; then
		        sudo cp $HOME/massa/massa-node/config/node_privkey.key $HOME/massa_backup/node_privkey.key
	        fi
            if grep -q "wrong password" <<< `cd $HOME/massa/massa-client/; ./massa-client -p "$massa_password" 2>&1; cd`; then
                echo Wrong password!
                return 1 2>/dev/null; exit 1
             fi
            massa_version=`wget -qO- https://api.github.com/repos/massalabs/massa/releases/latest | jq -r ".tag_name"`
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
                . <(wget -qO- https://raw.githubusercontent.com/SecorD0/Massa/main/insert_variables.sh)
                sudo cp $HOME/massa_backup/node_privkey.key $HOME/massa/massa-node/config/node_privkey.key
                configv6
                sudo cp $HOME/massa_backup/wallet.dat $HOME/massa/massa-client/wallet.dat
            else
                echo Archive is not downloaded!
            fi
            rm -rf $HOME/massa.tar.gz
}

# Autobuy rolls

autobuy() {

cd /root
sleep 1
 # Create script 
sudo tee /root/rollsup.sh > /dev/null <<EOF
#!/bin/sh
cd /root/massa/massa-client
#Set variables
catt=/usr/bin/cat
passwd=\$(\$catt \$HOME/massapasswd)
candidat=\$(./massa-client wallet_info -p "\$passwd"|grep 'Rolls'|awk '{print \$4}'| sed 's/=/ /'|awk '{print \$2}')
massa_wallet_address=\$(./massa-client -p "\$passwd" wallet_info |grep 'Address'|awk '{print \$2}')
tmp_final_balans=\$(./massa-client -p "\$passwd" wallet_info |grep 'Balance'|awk '{print \$3}'| sed 's/=/ /'|sed 's/,/ /'|awk '{print \$2}')
final_balans=\${tmp_final_balans%%.*}
averagetmp=\$(\$catt /proc/loadavg | awk '{print \$1}')
node=\$(./massa-client -p "\$passwd" get_status |grep 'Error'|awk '{print \$1}')
if [ -z "\$node" ]&&[ -z "\$candidat" ];then
echo \`/bin/date +"%b %d %H:%M"\` "(rollsup) Node is currently offline" >> /root/rolls.log
elif [ \$candidat -gt "0" ];then
echo "Ok" > /dev/null
elif [ \$final_balans -gt "99" ]; then
echo \`/bin/date +"%b %d %H:%M"\` "(rollsup) The roll flew off, we check the number of coins and try to buy" >> /root/rolls.log
resp=\$(./massa-client -p "\$passwd" buy_rolls \$massa_wallet_address 1 0)
else
echo \`/bin/date +"%b %d %H:%M"\` "(rollsup) Not enough coins to buy a roll from you \$final_balans, minimum 100" >> /root/rolls.log
fi
EOF
sleep 1
#Add cron
printf "SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/3 * * * * root /bin/bash /root/rollsup.sh > /dev/null 2>&1
" > /etc/cron.d/massarolls
sleep 1
#pass
sudo tee $HOME/massapasswd > /dev/null <<EOF
$massa_password
EOF
echo "Done"
}

uninstall() {
cd /root
sudo rm $HOME/rollsup.sh $HOME/massapasswd
sudo rm /etc/cron.d/massarolls
sudo systemctl stop massad
	if [ ! -d $HOME/massa_backup ]; then
		mkdir $HOME/massa_backup
		sudo cp $HOME/massa/massa-client/wallet.dat $HOME/massa_backup/wallet.dat
		sudo cp $HOME/massa/massa-node/config/node_privkey.key $HOME/massa_backup/node_privkey.key
	fi
	if [ -f $HOME/massa_backup/wallet.dat ] && [ -f $HOME/massa_backup/node_privkey.key ]; then
		rm -rf $HOME/massa/ /etc/systemd/system/massa.service /etc/systemd/system/massad.service
		sudo systemctl daemon-reload
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n massa_log -da
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n massa_client -da
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n massa_cli_client -da
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n massa_node_info -da
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n massa_wallet_info -da
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n massa_buy_rolls -da
        echo "Done"
	else
		echo No backup of the necessary files was found, delete the node manually!
	fi	
}
# Actions
sudo apt install net-tools wget -y &>/dev/null
cd
$function