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
if [ ! -n "$IPV6" ]; then
	printf "Enter your ipv6 address: "
    read IPV6 
    echo 'export PORT='{$IPV6} >> $HOME/.bash_profile
	fi
  echo -e '\n\e[42mYour ipv6 address:' $MAIL '\e[0m\n'
echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
	. $HOME/.bash_profile
sleep 1
#Make conf
if [ ! -d $HOME/massa/massa-node/config/ ]; then
    echo -e '\n\e[42m Massa is not installed!\e[0m\n'
    exit
    else
rm $HOME/massa/massa-node/config/config.toml
  sleep 1

tee <<EOF >/dev/null $HOME/massa/massa-node/config/config.toml
routable_ip = "$IPV6"
EOF

sleep 1
systemctl restart massad
fi