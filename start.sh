#!/bin/bash

#checks
clear
[[ $EUID -eq 0 ]] || (echo "Must run as root user."; exit 1)
wget -q --spider www.google.com || (echo "The network is not online."; exit 1)
[[ $(lsb_release -is) == "Debian" ]] || (echo "This script only works with Debian Linux."; exit 1)

#initialize
clear
read -p "Enter a hostname for this server. : "
hostnamectl set-hostname $REPLY
sed -i "s/$HOSTNAME/$REPLY/g" /etc/hosts
dpkg-reconfigure locales
dpkg-reconfigure tzdata
apt update && apt install -y cron openssh-server
sed -i '0,/.*PermitRootLogin.*/s//PermitRootLogin yes/' /etc/ssh/sshd_config
mem=$(awk '/MemTotal/ {print $2 / 1000000}' /proc/meminfo)
if [[ ${mem%.*} -lt 1 ]]
then wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/setup1.sh -O /root/.bash_profile
else wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/setup2.sh -O /root/.bash_profile
fi
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
systemctl reboot
exit
