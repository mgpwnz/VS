#!/bin/bash

ipv6=$(ifconfig | grep "scopeid 0x0<global>" | awk '{ print $2 }')
while true
do

# Menu

PS3='Select an action: '
options=("Change massa config" "Enable ipv6 ONLY Contabo" "Enable autobuy rolls" "Detete autobuy rolls" "Exit")
select opt in "${options[@]}"
               do
                   case $opt in                           

"Enable ipv6 ONLY Contabo")
# Change plan
sed -i "/net.ipv6.conf.all.disable_ipv6.*/d" /etc/sysctl.conf && sysctl -q -p && echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6 && sed -i "s/#//" /etc/netplan/01-netcfg.yaml && netplan generate && netplan apply
echo " Ipv6 Enable"
break
;;


"Change massa config")
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
exit
;;
"Enable autobuy rolls")
# Create script 
cd /root
sleep 1
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
printf "SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/3 * * * * root /bin/bash /root/rollsup.sh > /dev/null 2>&1
" > /etc/cron.d/massarolls
sleep 1
sudo tee $HOME/massapasswd > /dev/null <<EOF
$massa_password
EOF
echo " script Enable"
break
;;
"Delete autobuy rolls")
/usr/bin/rm /root/rollsup.sh
/usr/bin/rm /etc/cron.d/massarolls
echo " Done"
break
;;
"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done