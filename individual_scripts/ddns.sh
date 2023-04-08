#!/bin/bash
echo "Installing DuckDNS."
tee /etc/NetworkManager/dispatcher.d/99-ddns  > /dev/null <<'EOT'
#!/bin/sh
token=enter_token
domain=enter_domain
if [ "$2" = "up" ]
then
  sleep 15
  ipv6addr=$(curl -s https://api6.ipify.org)
  ipv4addr=$(curl -s https://api.ipify.org)
  curl -s "https://www.duckdns.org/update?domains=$domain&token=$token&ip=$ipv4addr&ipv6=$ipv6addr"
fi
exit 0
EOT
chmod +x /etc/NetworkManager/dispatcher.d/99-ddns  
read -p "Enter the token from duckdns.org: " token
sed -i "s/enter_token/$token/g" /etc/NetworkManager/dispatcher.d/99-ddns
read -p "Enter the domain from duckdns.org: " domain
sed -i "s/enter_domain/$domain/g" /etc/NetworkManager/dispatcher.d/99-ddns
cat <(crontab -l) <(echo "0 */2 * * * /etc/NetworkManager/dispatcher.d/99-ddns") | crontab -
exit
