#!/bin/bash

#checks
clear
if [[ $EUID -ne 0 ]]
then
  read -n 1 -s -r -p "Run as "root" user. Press any key to exit."
  exit
fi
if ! wget -q --spider www.google.com
then
  read -n 1 -s -r -p "The network is not online. Press any key to exit."
  exit
fi
if [[ $(lsb_release -is) != @(Debian|Ubuntu) ]]
then
  read -n 1 -s -r -p "This script does not work with $(lsb_release -is). Press any key to exit."
  exit
fi

#initialize
mem=$(awk '/MemTotal/ {print $2 / 1000000}' /proc/meminfo)
if [[ ${mem%.*} -lt 1 ]]
then
  wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/setup1.sh -O /root/setup.sh
else
  wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/setup2.sh -O /root/setup.sh
fi
chmod +x /root/setup.sh
if [[ $(ls /sys/class/net | grep ^e | wc -w) == 1 ]]
then
  adapt=$(ls /sys/class/net | grep ^e)
else
  ip route
  PS3="Select the network adapter that this server will use to connect: "
  select adapt in $(ls /sys/class/net | grep ^e)
  do
    break
  done
fi
dpkg-reconfigure locales
dpkg-reconfigure tzdata
clear
read -p "Enter a hostname for this server. : " serv
hostnamectl set-hostname $serv
sed -i "s/$HOSTNAME/$serv/g" /etc/hosts
if [[ $(lsb_release -is) == "Ubuntu" ]]
then
  add-apt-repository -y ppa:mozillateam/ppa
  add-apt-repository -y ppa:qbittorrent-team/qbittorrent-stable
fi
apt update
apt autopurge -y network-manager netplan.io ifupdown isc-dhcp-client openvpn unattended-upgrades cloud-init firefox needrestart ufw
rm -rf /etc/NetworkManager /etc/netplan /etc/network /etc/dhcp /var/log/unattended-upgrades /etc/cloud
apt install -y networkd-dispatcher policykit-1 openssh-server
sed -i '0,/.*PermitRootLogin.*/s//PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl --quiet unmask systemd-networkd
systemctl --quiet enable systemd-networkd
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
tee /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf > /dev/null <<EOT
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --interface=$adapt --timeout=30
EOT
tee /etc/systemd/network/20-wired.network > /dev/null <<EOT
[Match]
Name=$adapt

[Network]
DHCP=yes
EOT
echo "bash /root/setup.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
systemctl reboot
exit
