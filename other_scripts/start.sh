#!/bin/bash

#checks
clear
if [[ $EUID -ne 0 ]]
then
  read -n 1 -s -r -p "Run as "root" user. Press any key to exit."
  exit
fi
if ! wget -q --spider http://google.com
then
  read -n 1 -s -r -p "The network is not online. Press any key to exit."
  exit
fi

#initialize
read -p "Enter a hostname for this server. : " serv
hostnamectl set-hostname $serv
sed -i "s/$HOSTNAME/$serv/g" /etc/hosts
dpkg-reconfigure locales
dpkg-reconfigure tzdata
apt update
systemctl --quiet disable NetworkManager
apt autopurge -y network-manager netplan.io
rm -rf /etc/NetworkManager /etc/netplan
apt install -y --install-recommends ifupdown
systemctl --quiet unmask systemd-networkd
systemctl --quiet enable systemd-networkd
tee /etc/network/interfaces > /dev/null <<EOT
auto lo
iface lo inet loopback
EOT
eth=$(ip route | awk '/kernel/ { print $3 }')
read -n 1 -p "Do you want to setup a static IP address on this server? y/n: " cont
if [[ $cont == "y" ]]
then
  net=$(ip route | awk '/default/ { print $3 }' | cut -d "." -f 1-3)
  read -p "Enter a static IP address for the server: $net." add
  tee -a /etc/network/interfaces > /dev/null <<EOT

auto $eth
iface $eth inet static
        address $net.$add/24
        gateway $(ip route | awk '/default/ { print $3 }')
        dns-nameservers 8.8.8.8 1.1.1.1
iface $eth inet6 dhcp
EOT
else
  tee -a /etc/network/interfaces > /dev/null <<EOT

auto $eth
iface $eth inet dhcp
iface $eth inet6 dhcp
EOT
fi
wget https://raw.githubusercontent.com/ctonton/homeserver/main/setup1.sh -O setup.sh
chmod +x setup1.sh
echo "bash /root/setup.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
reboot
