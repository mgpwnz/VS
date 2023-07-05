#!/bin/bash 
while true; do 
  status=$(docker exec -it shardeum-dashboard operator-cli status | awk '/state:/ {print $NF}')
   if [[ "$status" == *"top"* ]]
   then 
  docker exec -it shardeum-dashboard operator-cli start 
  sleep 20 
  status=$(docker exec -it shardeum-dashboard operator-cli status | awk '/state:/ {print $NF}')
  else
  sleep 1
  fi 
   #wait 
  sleep 600
done