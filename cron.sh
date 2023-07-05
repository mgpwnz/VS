#!/bin/bash 
#create script
wget -q -O status.sh https://raw.githubusercontent.com/mgpwnz/VS/main/status.sh && chmod +x status.sh
sleep 1
#Add cron
printf "SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/1 * * * * root /bin/bash /root/status.sh > /dev/null 2>&1
" > /etc/cron.d/status_shardeum