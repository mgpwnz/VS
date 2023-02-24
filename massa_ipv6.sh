#!/bin/bash

ipv6=$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')
while true
do

# Menu

PS3='Select an action: '
options=("Change massa config" "Enable ipv6 Contabo" "Exit")
select opt in "${options[@]}"
               do
                   case $opt in                           

"Enable ipv6 Contabo")
# Change plan
sed -i "/net.ipv6.conf.all.disable_ipv6.*/d" /etc/sysctl.conf && sysctl -q -p && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 && sed -i "s/#//" /etc/netplan/01-netcfg.yaml && netplan generate && netplan apply
echo " Ipv6 Enable"
break
;;


"Change massa config")
ipv6=$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')

if [ -z $ipv6 ]; then
echo "You dont have IPV6"
elif [ ! -d $HOME/massa/ ]; then
    echo -e "\e[32m"Massa is not install"\e[39m"
else
    sed -i -e "s%routable_ip *=.*%routable_ip = \"$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')\"%g" $HOME/massa/massa-node/config/config.toml
    cat $HOME/massa/massa-node/config/config.toml
    sleep 2
    systemctl restart massad
fi
exit
;;

"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done