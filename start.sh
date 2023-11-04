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
adapt=$(ls /sys/class/net | grep ^e)
gate=$(ip route | awk '/default/ { print $3 }')
add=$(echo $gate | cut -d "." -f 1-3)
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
apt autopurge -y network-manager netplan.io ifupdown isc-dhcp-client openvpn unattended-upgrades cloud-init firefox needrestart
rm -rf /etc/NetworkManager /etc/netplan /etc/network /etc/dhcp /var/log/unattended-upgrades /etc/cloud
apt install -y systemd-resolved networkd-dispatcher policykit-1 openssh-server ufw
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
EOT
echo
read -p "Do you want to setup a static IP address on this server? y/n: " cont
if [[ $cont == "y" ]]
then
  echo
  read -p "Enter a static IP address for the server: $add." ress
  tee -a /etc/systemd/network/20-wired.network > /dev/null <<EOT
Address=$add.$ress/24
Gateway=$gate
DNS=$gate
EOT
else
  echo "DHCP=yes" >> /etc/systemd/network/20-wired.network
  tee /etc/networkd-dispatcher/routable.d/30-fixufw > /dev/null <<'EOT'
#!/bin/bash
old=0
new=$(ip route | grep "ADAPT proto kernel" | cut -d " " -f 1)
if [ $old != $new ]
then
  ufw delete allow from $old
  ufw allow from $new
  ufw reload
  sed -i "s~$old~$new~g" /etc/networkd-dispatcher/routable.d/30-fixufw
fi
exit
EOT
  sed -i "s/ADAPT/$adapt/g" /etc/networkd-dispatcher/routable.d/30-fixufw
  chmod +x /etc/networkd-dispatcher/routable.d/30-fixufw
fi
mem=$(grep MemTotal /proc/meminfo | awk '{print $2 / 1000000}')
if [[ ${mem%.*} -lt 1 ]]
then
  wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/setup1.sh -O /root/setup.sh
else
  wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/setup2.sh -O /root/setup.sh
fi
chmod +x /root/setup.sh
echo "bash /root/setup.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
systemctl reboot
exit
