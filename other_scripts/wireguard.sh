#!/bin/bash
clear
loo=0
until [ $loo -eq 5 ]
do
  echo
  echo "1 - Install WireGuard"
  echo "2 - Add user"
  echo "3 - Remove user"
  echo "4 - Uninstall Wireguard"
  echo "5 - Quit"
  echo
  read -p "Enter selection: :" loo
  if [ $loo -eq 1 ]
  then
    apt-get update
    apt-get install -y wireguard qrencode
    wg genkey | tee /etc/wireguard/private.key
    chmod go= /etc/wireguard/private.key
    cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key
    printf $(date +%s%N)$(cat /var/lib/dbus/machine-id) | sha1sum | cut -c 31- | tee ipv6
    sed -i '1 s/./fd&/' ipv6
    sed -i 's/..../&:/g' ipv6
    sed -i 's/  -/:1\/64/' ipv6
    tee /etc/wireguard/wg0.conf > /dev/null << EOT
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = 10.10.100.1/24
Address = $(cat ./ipv6)
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
    systemctl enable wg-quick@wg0.service
    rm ipv6
    clear
    loo=0
  fi
  if [ $loo -eq 2 ]
  then
    if [  ]
    then
      mkdir /root/wgusers
    fi
    read "Input a name for the new user: " new
    clear
    loo=0
  fi
  if [ $loo -eq 3 ]
  then
    read "Input the name of the user to remove: " old
    clear
    loo=0
  fi
  if [ $loo -eq 4 ]
  then
    systemctl stop wg-quick@wg0.service
    systemctl disable wg-quick@wg0.service
    rm -rf /root/wgusers
    apt-get remove --purge --autoremove wireguard qrencode
    ufw delete allow from 10.10.100.0/24
    ufw delete allow 51820/udp
    clear
    loo=0
  fi
  if [ $loo -eq 5 ]
  then
    exit 0
  else
    clear
    echo "Invalid selection."
    loo=0
  fi
done

