#!/bin/bash
tee /boot/armbianEnv.txt > /dev/null <<EOT
board_name=hc1
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
EOT
apt update
systemctl --quiet disable NetworkManager
apt autopurge -y network-manager netplan.io
rm -rf /etc/NetworkManager /etc/netplan
apt install -y --install-recommends ifupdown
systemctl --quiet unmask systemd-networkd
systemctl --quiet enable systemd-networkd
net=$(ip route | awk '/default/ { print $3 }' | cut -d "." -f 1-3)
read -p "Enter a static IP address for the server: $net." add
tee /etc/network/interfaces > /dev/null <<EOT
auto lo
iface lo inet loopback

auto $(ls /sys/class/net | grep en)
iface $(ls /sys/class/net | grep en) inet static
        address $net.$add/24
        gateway $(ip route | awk '/default/ { print $3 }')
        dns-nameservers 8.8.8.8 1.1.1.1
EOT
wget https://raw.githubusercontent.com/ctonton/homeserver/main/setup2.sh -O setup.sh
chmod +x setup.sh
echo "bash /root/setup.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
reboot
