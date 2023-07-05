#!/bin/bash 
#create script
sudo tee /root/status_shardeum.sh > /dev/null <<EOF
#!/bin/sh
while true; do 
  status=$(docker exec -it shardeum-dashboard operator-cli status | awk '/state:/ {print $NF}')
   if [[ "$status" == *"top"* ]]
   then 
  docker exec -it shardeum-dashboard operator-cli start 
  sleep 10 
  status=$(docker exec -it shardeum-dashboard operator-cli status | awk '/state:/ {print $NF}')
  else
  sleep 1
  fi 
done
EOF
sleep 1
#Add cron
printf "SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/15 * * * * root /bin/bash /root/status_shardeum.sh > /dev/null 2>&1
" > /etc/cron.d/status_shardeum