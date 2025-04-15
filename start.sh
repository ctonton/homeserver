#!/bin/bash

#checks
clear
[[ $EUID -eq 0 ]] || (echo "Must run as root user."; exit 1)
wget -q --inet4-only --spider www.google.com || (echo "The network is not online."; exit 1)
[[ $(lsb_release -is) == "Debian" ]] || (echo "This script only works with Debian Linux."; exit 1)

#initialize
apt autopurge -y unattended-upgrades
apt update; apt full-upgrade
rm -rf /var/log/unattended-upgrades
apt install -y cron curl exfat-fuse gzip locales nano ntfs-3g openssh-server tar tzdata unzip xfsprogs
sed -i '0,/.*PermitRootLogin.*/s//PermitRootLogin yes/' /etc/ssh/sshd_config
clear; read -p "Enter a hostname for this server. : "
hostnamectl set-hostname $REPLY
sed -i "s/$HOSTNAME/$REPLY/g" /etc/hosts
dpkg-reconfigure locales
dpkg-reconfigure tzdata
mem=$(awk '/MemTotal/ {print $2 / 1000000}' /proc/meminfo)
if [[ ${mem%.*} -lt 1 ]]; then
  wget -q --show-progress --inet4-only https://github.com/ctonton/homeserver/raw/main/scripts/setup1.sh -O /root/.bash_profile
else
  wget -q --show-progress --inet4-only https://github.com/ctonton/homeserver/raw/main/scripts/setup2.sh -O /root/.bash_profile
fi
chmod +x /root/.bash_profile
clear; read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
reboot
exit 0
