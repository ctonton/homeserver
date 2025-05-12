#!/bin/bash
apt update
apt install -y networkd-dispatcher polkitd systemd-resolved
apt autopurge -y network-manager netplan.io ifupdown isc-dhcp-client resolvconf openvpn
rm -rf /etc/NetworkManager /etc/netplan /etc/network /etc/dhcp
systemctl --quiet unmask systemd-networkd
systemctl --quiet enable systemd-networkd
rm -rf /etc/systemd/network/*
if [[ $(ls /sys/class/net | grep ^e | wc -w) -eq 1 ]]; then
  tee /etc/systemd/network/10-wired.network <<EOT
[Match]
Name=$(ls /sys/class/net | grep ^e)

[Network]
DHCP=yes
EOT
else
  tee /etc/systemd/network/10-br0.netdev <<EOT
[NetDev]
Name=br0
Kind=bridge
MACAddress=$(cat /sys/class/net/e*/address | head -n1)
EOT
  tee /etc/systemd/network/20-br0.network <<EOT
[Match]
Name=$(ls /sys/class/net | grep ^e | xargs)

[Network]
Bridge=br0
EOT
  tee /etc/systemd/network/30-br0.network <<EOT
[Match]
Name=br0

[Network]
DHCP=yes
EOT
fi
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
tee /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf <<EOT
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --any --timeout=30
EOT
exit 0
