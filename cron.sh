#!/bin/bash 
#create script

sleep 1
#Add cron
printf "SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/15 * * * * root /bin/bash /root/status_shardeum.sh > /dev/null 2>&1
" > /etc/cron.d/status_shardeum