#!/bin/bash
clear
echo "Setup WireGuard"
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
  read -p "Enter selection: " loo
  if [ $loo -eq 1 ]
  then
    apt-get update
    apt-get install -y wireguard qrencode
    wg genkey | tee /etc/wireguard/private.key
    chmod go= /etc/wireguard/private.key
    cat /etc/wireguard/private.key | wg pubkey | tee /etc/wireguard/public.key
    printf $(date +%s%N)$(cat /var/lib/dbus/machine-id) | sha1sum | cut -c 31- | tee ip6
    sed -i '1 s/./fd&/' ip6
    sed -i 's/..../&:/g' ip6
    sed -i 's/  -/:/' ip6
    eth=$(ip route | grep default | awk '{print $5}')
    read "Enter the public ip address or name of this server: " ddns
    tee /etc/wireguard/wg0.conf > /dev/null << EOT
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = 10.10.100.1/24, $(cat ./ip6)1/64
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
    ufw disable
    ufw enable
    sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
    sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
    sysctl -p
    sed -i '/^WebUI\\AuthSubnetWhitelist=/ s/$/,10.10.100.0\/24/' /root/.config/qBittorrent/qBittorrent.conf
    systemctl enable wg-quick@wg0.service
    systemctl start wg-quick@wg0.service
    rm ip6
    clear
    echo "WireGuard server is running."
    loo=2
  fi
  if [ $loo -eq 2 ]
  then
    mkdir -p /root/wgusers
    read "Input a name for the new user: " new
    key=$(wg genkey)
    psk=$(wg genpsk)
    ip6=$(cat /etc/wireguard/wg0.conf | grep Address | awk '{print $4}' | cut -c-16)
    tee -a /etc/wireguard/wg0.conf > /dev/null << EOT
# BEGIN_PEER $new
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.10.100.${oct}/32, ${ip6}${oct}/128
# END_PEER $new
EOT
    tee /root/wgusers/${new}.conf > /dev/null << EOT
[Interface]
Address = 10.10.100.${oct}/24, ${ip6}${oct}/64
DNS = 8.8.8.8, 8.8.4.4
PrivateKey = $key

[Peer]
PublicKey = $(grep PrivateKey /etc/wireguard/wg0.conf | cut -d " " -f 3 | wg pubkey)
PresharedKey = $psk
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $(grep '^#ENDPOINT' /etc/wireguard/wg0.conf | awk '{print $2}'):$(grep ListenPort /etc/wireguard/wg0.conf | cut -d " " -f 3)
PersistentKeepalive = 25
EOT
    clear
    echo
    qrencode -t UTF8 < /root/wgusers/"$new.conf"
    echo -e '\xE2\x86\x91 That is a QR code containing your client configuration.'
    echo
    echo "$new added. Configuration available in /root/wgusers/"
    read -n 1 -s -r -p "Press any key to continue."
    clear
    echo "Client added"
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
