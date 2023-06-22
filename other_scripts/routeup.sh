tee /boot/armbianEnv.txt > /dev/null <<'EOT'
board_name=hc1
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
EOT
apt disable NetworkManager
apt autopurge network-manager netplan.io
rm -rf /etc/NetworkManager /etc/netplan
apt install -y ifupdown
apt unmask systemd-networkd
apt enable systemd-networkd
tee /etc/network/interfaces > /dev/null <<'EOT'
auto lo
iface lo inet loopback

auto enx001e0630bfc5
iface enx001e0630bfc5 inet static
	address 10.10.10.10/24
	gateway  10.10.10.1
	dns-nameservers 8.8.8.8 1.1.1.1
EOT

if dpkg -s network-manager &>/dev/null
then
  if ! systemctl is-enabled --quiet NetworkManager-wait-online.service
  then
    systemctl enable NetworkManager-wait-online.service
  fi
else
  if ! systemctl is-enabled --quiet systemd-networkd-wait-online.service
  then
    systemctl enable systemd-networkd-wait-online.service
  fi
fi
#tee /root/.config/qBittorrent/lanchk.sh > /dev/null <<'EOT'
#!/bin/bash
##if /sbin/ip route | grep "default"
#then
#  OLD=$(cat /root/.config/route | cut -d '/' -f 1)
#  NEW=$(/sbin/ip route | awk '/src/ { print $1 }' | cut -d '/' -f 1)
#  if [[ $OLD != $NEW ]]
#  then
#    sed -i "s/$OLD/$NEW/g" /root/.config/qBittorrent/qBittorrent.conf
#    ufw delete allow from $(cat /root/.config/route)
#    ufw allow from $(/sbin/ip route | awk '/src/ { print $1 }')
#    echo $(/sbin/ip route | awk '/src/ { print $1 }') > /root/.config/route
#  fi
#fi
#exit
#EOT
#chmod +x /root/.config/qBittorrent/lanchk.sh
