#!/bin/bash

while true
do


# Menu

PS3='Select an action: '
options=("Change massa config" "Enable ipv6 Contabo" "Exit")
select opt in "${options[@]}"
               do
                   case $opt in                           

"Enable ipv6 Contabo")
echo "============================================================"
echo "Enable ipv6 Contabo"
echo "============================================================"
# Change plan
sed -i "/net.ipv6.conf.all.disable_ipv6.*/d" /etc/sysctl.conf && sysctl -q -p && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 && sed -i "s/#//" /etc/netplan/01-netcfg.yaml && netplan generate && netplan apply
break
;;


"Change massa config")
if [ ! $IPV6 ]; then
echo "============================================================"
echo "Enter your ipv6 address"
echo "============================================================"
read IPV6
echo export IPV6=${IPV6} >> $HOME/.bash_profile
source $HOME/.bash_profile
fi
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
. $HOME/.bash_profile
break
;;

"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done