#!/bin/bash
# Default variables
function="install"
# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -ip|--ipv6)
            function="ipv6"
            shift
            ;;
        -cb|--contabo)
            function="contabo"
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
        -mw|--massa_wallet)
            function="massa_wallet"
            shift
            ;;
        *|--)
		break
		;;
	esac
done
# change config
config() {
    sudo systemctl stop massad
    sudo tee <<EOF >/dev/null $HOME/massa/massa-node/config/config.toml
[protocol]
routable_ip = "`wget -qO- eth0.me`"
EOF
	sudo systemctl restart massad
}
install() {
        if [ ! -n "$massa_password" ]; then
		echo Create password and save it in the variable!
		read -p "Enter passwd: " massa_password
		echo 'export massa_password='${massa_password} >> $HOME/.bash_profile
	    fi
        if [ -d $HOME/massa/ ]; then
            update
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
            config
            . <(wget -qO- https://raw.githubusercontent.com/SecorD0/Massa/main/insert_variables.sh)
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
            echo The node was started!
            else
                rm -rf $HOME/massa.tar.gz
                echo Archive with binary downloaded unsuccessfully!
            fi
        fi
}
#UPDATE
update() {
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
                config
                sudo cp $HOME/massa_backup/wallet.dat $HOME/massa/massa-client/wallet.dat
            else
                echo Archive with binary downloaded unsuccessfully!
            fi
            rm -rf $HOME/massa.tar.gz
}
# change config
ipv6() {
    ipv6=$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')

        if [ -z $ipv6 ]; then
            echo -e "\e[32m"You dont have IPV6"\e[39m"
        elif [ ! -d $HOME/massa/ ]; then
            echo -e "\e[32m"Massa is not install"\e[39m"
        else
    sed -i -e "s%routable_ip *=.*%routable_ip = \"$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')\"%g" $HOME/massa/massa-node/config/config.toml
    cat $HOME/massa/massa-node/config/config.toml
    sleep 2
    systemctl restart massad
fi
}
# Change plan
contabo() {
    
    sed -i "/net.ipv6.conf.all.disable_ipv6.*/d" /etc/sysctl.conf && sysctl -q -p && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 && sed -i "s/#//" /etc/netplan/01-netcfg.yaml && netplan generate && netplan apply
    echo " Ipv6 Enable"
}
# Autobuy rolls

autobuy() {

cd /root
sleep 1
 # Create script 
sudo tee /root/rollsup.sh > /dev/null <<EOF
#!/bin/sh
#Версия 0.14
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
massa_wallet(){
cd $HOME/massa/massa-client
#Set variables
printf_n(){ printf "$1\n" "${@:2}"; }
wallet_info=`./massa-client -p "$massa_password" -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	if [ "$raw_output" = "true" ]; then
		printf_n "`jq -r "[.[]]" <<< "$wallet_info"`"
	else
		local staking_addresses=`./massa-client -p "$massa_password" -j node_get_staking_addresses`
		local wallets=`jq -r "to_entries[]" <<< "$wallet_info" | tr -d '[:space:]' | sed 's%}{%} {%g'`
		printf_n
		for wallet in $wallets; do
			local address=`jq -r ".key" <<< "$wallet"`
			printf "1" "$address"
			if [ "$address" = "$main_address" ]; then
				printf_n "2"
			else
				printf_n
			fi
			if [ "$secret_keys" = "true" ]; then
				local secret_key=`jq -r ".value.keypair.secret_key" <<< "$wallet"`
				printf_n "3" "$secret_key"
			fi
			local public_key=`jq -r ".value.keypair.public_key" <<< "$wallet"`
			printf_n "4" "$public_key"
			if grep -q "$address" <<< "$staking_addresses"; then
				printf_n "5"
			else
				printf_n "6"
			fi
			local balance=`jq -r ".value.address_info.candidate_balance" <<< "$wallet"`
			printf_n "7" "$balance"
			local total_rolls=`jq -r ".value.address_info.candidate_rolls" <<< "$wallet"`
			printf_n "8" "$total_rolls"
			local active_rolls=`jq -r ".value.address_info.active_rolls" <<< "$wallet"`
			printf_n "9" "$active_rolls"
			printf_n
		done
	fi
}
uninstall() {
cd /root
sudo rm $HOME/rollsup.sh $HOME/massapasswd
sudo rm /etc/cron.d/massarolls
echo "Done"
}
# Actions
sudo apt install net-tools wget -y &>/dev/null
cd
$function