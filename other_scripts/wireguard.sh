#!/bin/bash

apt-get update
apt-get install -y wireguard qrencode

wg genkey | tee /etc/wireguard/private.key
chmod go= /etc/wireguard/private.key
cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key

tee /etc/wireguard/wg0.conf > /dev/null << EOT
[Interface]
PrivateKey = $(/sbin/cat /etc/wireguard/private.key)
Address = 10.10.100.1/24, fd24:609a:6c18::1/64
ListenPort = 51820
SaveConfig = true
PostUp = ufw route allow in on wg0 out on eth0
PostUp = iptables -t nat -I POSTROUTING -o eth0 -j MASQUERADE
PostUp = ip6tables -t nat -I POSTROUTING -o eth0 -j MASQUERADE
PreDown = ufw route delete allow in on wg0 out on eth0
PreDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PreDown = ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOT

ufw allow from 10.10.100.0/24
ufw allow 51820/udp
sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
sed -i '/^WebUI\\AuthSubnetWhitelist=/ s/$/,10.10.100.0\/24/' /root/.config/qBittorrent/qBittorrent.conf
sudo systemctl enable wg-quick@wg0.service
