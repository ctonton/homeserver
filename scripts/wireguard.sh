#!/bin/bash
clear
echo "Setup WireGuard"
loop=0
until [ $loop -eq 6 ]; do
  echo
  echo "1 - Install WireGuard"
  echo "2 - Add client"
  echo "3 - Show client QR"
  echo "4 - Remove client"
  echo "5 - Uninstall Wireguard"
  echo "6 - Quit"
  echo
  read -p "Enter selection: " loop
  if [[ $loop -eq 1 ]]; then
    if ! dpkg -l | grep -q 'linux-headers'; then
      echo "Wireguard can not run. Install linux-headers for your system and then try again."
      read -n 1 -s -r -p "Press any key to exit."
      exit
    fi
    apt update
    apt install -y wireguard-tools qrencode ufw
    PS3="Select the network adapter to use: "
    clear
    select eth in $(ls /sys/class/net); do break; done
    echo
    read -p "Enter the public ip address or name of this server: "
    echo "Endpoint = $REPLY:5120" > /etc/wireguard/variables
    ip6=$(echo $(date +%s%N)$(cat /var/lib/dbus/machine-id) | sha1sum | cut -c 31- | sed '1 s/./fd&/' | sed 's/..../&:/g' | sed 's/  -/:/')
    echo "$ip6" >> /etc/wireguard/variables
    ufw allow ssh
    ufw --force enable
    mkdir -p /etc/wireguard
    wg genkey | tee /etc/wireguard/private.key
    chmod go= /etc/wireguard/private.key
    cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key
    tee /etc/wireguard/wg0.conf > /dev/null << EOT
[Interface]
Address = 10.10.100.1/24, ${ip6}1/64
SaveConfig = false
PostUp = ufw route allow in on wg0 out on $eth
PostUp = iptables -t nat -I POSTROUTING -o $eth -j MASQUERADE
PostUp = ip6tables -t nat -I POSTROUTING -o $eth -j MASQUERADE
PreDown = ufw route delete allow in on wg0 out on $eth
PreDown = iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
PreDown = ip6tables -t nat -D POSTROUTING -o $eth -j MASQUERADE
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/private.key)
EOT
    ufw allow from 10.10.100.0/24
    ufw allow 51820/udp
    ufw reload
    sed -i 's/.*forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sed -i 's/.*forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
    sysctl --system
    systemctl enable wg-quick@wg0.service
    systemctl start wg-quick@wg0.service
    clear
    echo "WireGuard server is running."
  fi
  if [[ $loop -eq 2 ]]; then
    mkdir -p /root/clients
    read -p "Input a name for the new client: " client
    key=$(wg genkey)
    psk=$(wg genpsk)
    octet=2
    while grep 'AllowedIPs' /etc/wireguard/wg0.conf | cut -d "." -f 4 | cut -d "/" -f 1 | grep -q "$octet"; do (( octet++ )); done
    if [[ "$octet" -eq 255 ]]; then
      echo "253 clients are already configured. The WireGuard internal subnet is full!"
    else
      tee -a /etc/wireguard/wg0.conf > /dev/null << EOT

[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.10.100.${octet}/32, $(head -2 /etc/wireguard/variables)${octet}/128
EOT
    tee /root/clients/${client}.conf > /dev/null << EOT
[Interface]
Address = 10.10.100.${octet}/24, $(head -2 /etc/wireguard/variables)${octet}/64
DNS = 8.8.8.8, 8.8.4.4
PrivateKey = $key

[Peer]
PublicKey = $(awk '/PrivateKey/ {print $3}' /etc/wireguard/wg0.conf | wg pubkey)
PresharedKey = $psk
AllowedIPs = 0.0.0.0/0, ::/0
$(head -1 /etc/wireguard/variables)
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
  fi
  if [[ $loop -eq 3 ]]; then
    PS3="Select the name of the client to display: "
    select client in $(ls /root/clients | grep '.conf' | cut -d '.' -f1); do break; done
    qrencode -t UTF8 < /root/clients/"$client.conf"
    echo "This is a QR code containing ${client}'s client configuration."
    read -n 1 -s -r -p "Press any key to continue."
    clear
    echo "Setup WireGuard"
  fi
  if [[ $loop -eq 4 ]]; then
    PS3="Select the name of the client to remove: "
    select client in $(ls /root/clients | grep '.conf' | cut -d '.' -f1); do break; done
    psk=$(cat /root/clients/"$client.conf" | awk '/PresharedKey/ {print $3}')
    line=$(cat wg0.conf | sed -n "/$psk/{=;q;}")
    sed -i "$(expr $line - 3),$(expr $line + 1)d" /etc/wireguard/wg0.conf
    rm /root/clients/$client.*
    systemctl reload wg-quick@wg0
    clear
    echo "$client removed"
  fi
  if [[ $loop -eq 5 ]]; then
    systemctl stop wg-quick@wg0.service
    systemctl disable wg-quick@wg0.service
    rm -rf /root/clients
    apt autopurge -y wireguard qrencode
    rm -rf /etc/wireguard/*
    ufw delete allow from 10.10.100.0/24
    ufw delete allow 51820/udp
    ufw reload
    sed -i 's/.*forward=1/#net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sed -i 's/.*forwarding=1/#net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
    sysctl --system
  fi
done
exit
