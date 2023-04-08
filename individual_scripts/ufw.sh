#!/bin/bash
echo "Setting up firewall."
apt-get install -y --no-install-recommends ufw
ufw allow from $(/sbin/ip route | awk '/src/ { print $1 }')
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 10.7.0.0/24
ufw allow 51820/udp
ufw logging off
ufw enable
exit
