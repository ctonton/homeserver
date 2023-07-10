#!/bin/bash
clear
echo "Setup WireGuard"
loo=0
until [ $loo -eq 5 ]
do
  echo
  echo "1 - Install WireGuard"
  echo "2 - Add client"
  echo "3 - Remove client"
  echo "4 - Uninstall Wireguard"
  echo "5 - Quit"
  echo
  read -p "Enter selection: " loo
  if [ $loo -eq 1 ]
  then
    apt-get update
    apt-get install -y wireguard qrencode
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
#ENDPOINT ${ddns}:51820
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
  if [ $loo -eq 2 ]
  then
    mkdir -p /root/clients
    read -p "Input a name for the new client: " new
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
#BEGIN_$new
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.10.100.${octet}/32, ${ip6}${octet}/128
#END_$new
EOT
    tee /root/clients/${new}.conf > /dev/null << EOT
[Interface]
Address = 10.10.100.${octet}/24, ${ip6}${octet}/64
DNS = 8.8.8.8, 8.8.4.4
PrivateKey = $key

[Peer]
PublicKey = $(awk '/PrivateKey/ {print $3}' /etc/wireguard/wg0.conf | wg pubkey)
PresharedKey = $psk
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $(awk '/#ENDPOINT/ {print $2}' /etc/wireguard/wg0.conf)
PersistentKeepalive = 25
EOT
    clear
    echo
    qrencode -t PNG -o /root/clients/"$new.png" -r /root/clients/"$new.conf"
    qrencode -t UTF8 < /root/clients/"$new.conf"
    echo "This is a QR code containing ${new}'s client configuration."
    echo "${new}'s configuration files is available in /root/clients"
    read -n 1 -s -r -p "Press any key to continue."
    systemctl reload wg-quick@wg0
    clear
    echo "$new added"
  fi
  if [ $loo -eq 3 ]
  then
    ls /root/clients | grep '.conf' | cut -d '.' -f1 > list
    PS3="Select the name of the client to remove: "
    select old in $(<list)
    do
    sed -i "/#BEGIN_$old/,/#END_$old/d" /etc/wireguard/wg0.conf
    rm /root/clients/$old.*
    systemctl reload wg-quick@wg0
    break
    done
    rm list
    clear
    echo "$old removed"
  fi
  if [ $loo -eq 4 ]
  then
    systemctl stop wg-quick@wg0.service
    systemctl disable wg-quick@wg0.service
    rm -rf /root/clients
    apt autopurge -y wireguard qrencode
    rm -rf /etc/wireguard
    ufw delete allow from 10.10.100.0/24
    ufw delete allow 51820/udp
    ufw reload
    sed -i '/forward=1/ s/./#&/' /etc/sysctl.conf
    sed -i '/forwarding=1/ s/./#&/' /etc/sysctl.conf
    sysctl -p
    exit
  fi
done
exit
