#!/bin/bash
log=$( journalctl -n 1 -u massad | grep thread | awk '{ print $15 }' )
while [ $log !eq thread: ]; do
sleep 60;
done



