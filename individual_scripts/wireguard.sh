#!/bin/bash
echo "Downloading WireGuard setup script to the root directory."
curl -LJ https://github.com/Nyr/wireguard-install/raw/master/wireguard-install.sh -o /root/setup-wireguard.sh
chmod +x /root/setup-wireguard.sh
bash /root/setup-wireguard.sh
sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
sed -i '/^WebUI\\AuthSubnetWhitelist=/ s/$/,10.7.0.0\/24/' /root/.config/qBittorrent/qBittorrent.conf
exit
