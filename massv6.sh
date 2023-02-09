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
#Ping ipv6
ping6 ipv6.google.com > $HOME/ping6 < "/dev/null"
sleep 2

#Set Var
catt=/usr/bin/cat
ping6=$($catt \$HOME/ping6)
if
    $ping6=""; then
    echo -e '\n\e[42mPlease enable ipv6\e[0m\n' && sleep 2
    fi
    