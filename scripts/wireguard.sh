#!/bin/bash
clear
echo "Setup WireGuard"
loop=0
until [ $loop -eq 6 ]
do
  echo
  echo "1 - Install WireGuard"
  echo "2 - Add client"
  echo "3 - Show client QR"
  echo "4 - Remove client"
  echo "5 - Uninstall Wireguard"
  echo "6 - Quit"
  echo
  read -p "Enter selection: " loop
  if [ $loop -eq 1 ]
  then
    apt update
    apt install -y wireguard qrencode ufw
    ufw allow ssh
    ufw --force enable
    mkdir -p /etc/wireguard
    wg genkey | tee /etc/wireguard/private.key
    chmod go= /etc/wireguard/private.key
    cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key
    ip6=$(echo $(date +%s%N)$(cat /var/lib/dbus/machine-id) | sha1sum | cut -c 31- | sed '1 s/./fd&/' | sed 's/..../&:/g' | sed 's/  -/:/')
    eth=$(ip route | awk '/kernel/ { print $3 }')
    clear
    read -p "Enter the public ip address or name of this server: " ddns
    tee /etc/wireguard/wg0.conf > /dev/null << EOT
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = 10.10.100.1/24, ${ip6}1/64
ListenPort = 51820
SaveConfig = true
PostUp = ufw route allow in on wg0 out on $eth
PostUp = iptables -t nat -I POSTROUTING -o $eth -j MASQUERADE
PostUp = ip6tables -t nat -I POSTROUTING -o $eth -j MASQUERADE
PreDown = ufw route delete allow in on wg0 out on $eth
PreDown = iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
PreDown = ip6tables -t nat -D POSTROUTING -o $eth -j MASQUERADE
#ENDPOINT $ddns
EOT
    ufw allow from 10.10.100.0/24
    ufw allow 51820/udp
    ufw reload
    sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
    sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
    sysctl -p
    systemctl enable wg-quick@wg0.service
    systemctl start wg-quick@wg0.service
    clear
    echo "WireGuard server is running."
  fi
  if [ $loop -eq 2 ]
  then
    mkdir -p /root/clients
    read -p "Input a name for the new client: " client
    key=$(wg genkey)
    psk=$(wg genpsk)
    ip6=$(cat /etc/wireguard/wg0.conf | grep Address | awk '{print $4}' | cut -c-16)
    octet=2
    while grep 'AllowedIPs' /etc/wireguard/wg0.conf | cut -d "." -f 4 | cut -d "/" -f 1 | grep -q "$octet"
    do
      (( octet++ ))
    done
    if [[ "$octet" -eq 255 ]]
    then
      echo "253 clients are already configured. The WireGuard internal subnet is full!"
      exit
    fi
    tee -a /etc/wireguard/wg0.conf > /dev/null << EOT
#BEGIN_$client
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.10.100.${octet}/32, ${ip6}${octet}/128
#END_$client
EOT
    tee /root/clients/${client}.conf > /dev/null << EOT
[Interface]
Address = 10.10.100.${octet}/24, ${ip6}${octet}/64
DNS = 8.8.8.8, 8.8.4.4
PrivateKey = $key

[Peer]
PublicKey = $(awk '/PrivateKey/ {print $3}' /etc/wireguard/wg0.conf | wg pubkey)
PresharedKey = $psk
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $(awk '/#ENDPOINT/ {print $2}' /etc/wireguard/wg0.conf):51820
PersistentKeepalive = 25
EOT
    clear
    echo
    qrencode -t PNG -o /root/clients/"$client.png" -r /root/clients/"$client.conf"
    qrencode -t UTF8 < /root/clients/"$client.conf"
    echo "This is a QR code containing ${client}'s client configuration."
    echo "${client}'s configuration file is available in /root/clients"
    read -n 1 -s -r -p "Press any key to continue."
    systemctl reload wg-quick@wg0
    clear
    echo "$client added"
  fi
  if [ $loop -eq 3 ]
  then
    PS3="Select the name of the client to display: "
    select client in $(ls /root/clients | grep '.conf' | cut -d '.' -f1)
    do
      qrencode -t UTF8 < /root/clients/"$client.conf"
      echo "This is a QR code containing ${client}'s client configuration."
      break
    done
    clear
    echo "Setup WireGuard"
  fi
  if [ $loop -eq 4 ]
  then
    PS3="Select the name of the client to remove: "
    select client in $(ls /root/clients | grep '.conf' | cut -d '.' -f1)
    do
      sed -i "/#BEGIN_$client/,/#END_$client/d" /etc/wireguard/wg0.conf
      rm /root/clients/$client.*
      systemctl reload wg-quick@wg0
      break
    done
    clear
    echo "$client removed"
  fi
  if [ $loop -eq 5 ]
  then
    systemctl stop wg-quick@wg0.service
    systemctl disable wg-quick@wg0.service
    rm -rf /root/clients
    apt autopurge -y wireguard qrencode
    rm -rf /etc/wireguard/*
    ufw delete allow from 10.10.100.0/24
    ufw delete allow 51820/udp
    ufw reload
    sed -i '/forward=1/ s/./#&/' /etc/sysctl.conf
    sed -i '/forwarding=1/ s/./#&/' /etc/sysctl.conf
    sysctl --system
    exit
  fi
done
exit
