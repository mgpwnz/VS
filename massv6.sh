#!/bin/bash
exists()
{
  command -v "$1" >/dev/null 2>&1
}
if exists curl; then
	echo ''
else
  sudo apt update && sudo apt install curl -y < "/dev/null"
fi
if [ -f "$bash_profile" ]; then
    . $HOME/.bash_profile
fi
#add ip
if [ ! $IPV6 ]; then
		read -p "Enter ipv6: " IPV6
	fi
    echo 'Your ipv6: ' $IPV6
echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
. $HOME/.bash_profile
sleep 1
#Make conf
if [ ! -d $HOME/massa/massa-node/config/ ]; then
    echo -e '\n\e[42m Massa is not installed!\e[0m\n'
    exit
    else
rm $HOME/massa/massa-node/config/config.toml &>/dev/null
sleep 1
echo "[network]
routable_ip = "$IPV6"
" > $HOME/massa/massa-node/config/config.toml 
sleep 1
systemctl restart massad
fi
 