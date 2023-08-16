#!/bin/bash
eth=$(ls /sys/class/net | grep e)
old=0.0.0.0/24
new=$(ip route | grep "$eth proto kernel" | cut -d " " -f 1)
if [ $old != $new ]; then
  ufw delete allow from $old
  ufw allow from $new
  ufw reload
  sed -i "s~$old~$new~g" "$0"
fi
exit
