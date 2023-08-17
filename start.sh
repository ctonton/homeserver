#!/bin/bash

#checks
clear
if [[ $EUID -ne 0 ]]
then
  read -n 1 -s -r -p "Run as "root" user. Press any key to exit."
  exit
fi
if [[ $(lsb_release -is) != "Debian" ]]
then
  read -n 1 -s -r -p "This script is written for the Debian OS. Press any key to exit."
  exit
fi
if ! wget -q --spider www.google.com
then
  read -n 1 -s -r -p "The network is not online. Press any key to exit."
  exit
fi

#initialize
dpkg-reconfigure locales
dpkg-reconfigure tzdata
clear
read -p "Enter a hostname for this server. : " serv
hostnamectl set-hostname $serv
sed -i "s/$HOSTNAME/$serv/g" /etc/hosts
apt update
systemctl --quiet disable NetworkManager
apt autopurge -y network-manager netplan.io
rm -rf /etc/NetworkManager /etc/netplan
apt install -y ifupdown isc-dhcp-client isc-dhcp-common openssh-server ufw
sed -i '0,/.*PermitRootLogin.*/s//PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl --quiet unmask systemd-networkd
systemctl --quiet enable systemd-networkd
eth=$(ip route | awk '/default/ { print $5 }')
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
tee /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf > /dev/null <<EOT
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --interface=$eth --timeout=30
EOT
tee /etc/network/interfaces > /dev/null <<EOT
auto lo
iface lo inet loopback

auto $eth
allow-hotplug $eth
iface $eth inet6 auto
EOT
echo
read -p "Do you want to setup a static IP address on this server? y/n: " cont
if [[ $cont == "y" ]]
then
  net=$(ip route | awk '/default/ { print $3 }' | cut -d "." -f 1-3)
  echo
  read -p "Enter a static IP address for the server: $net." add
  tee -a /etc/network/interfaces > /dev/null <<EOT
iface $eth inet static
        address $net.$add/24
        gateway $(ip route | awk '/default/ { print $3 }')
EOT
else
  echo "iface $eth inet dhcp" >> /etc/network/interfaces
  tee /etc/dhcp/dhclient-exit-hooks.d/fixufw > /dev/null <<'EOT'
#!/bin/bash
eth=adapter
old=0.0.0.0/24
if ([ $reason == "BOUND" ] || [ $reason == "RENEW" ])
then
  new=$(ip route | grep "$eth proto kernel" | cut -d " " -f 1)
else
  exit
fi
if [ $old != $new ]
then
  ufw delete allow from $old
  ufw allow from $new
  ufw reload
  sed -i "s~$old~$new~g" /etc/dhcp/dhclient-exit-hooks.d/fixufw
fi
exit
EOT
  sed -i "s/adapter/$eth/g" /etc/dhcp/dhclient-exit-hooks.d/fixufw
  chmod +x /etc/dhcp/dhclient-exit-hooks.d/fixufw
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
