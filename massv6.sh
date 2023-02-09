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
#change ip
if [ ! $IPV6 ]; then
		read -p "Enter ipv6: " IPV6
	fi
echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
sleep 1
    