#!/bin/bash
echo
echo "Installing DuckDNS."
mkdir /root/.ddns
tee /root/.ddns/duck.sh > /dev/null <<'EOT'
#!/bin/bash
domain=enter_domain
token=enter_token
ipv6addr=$(curl -s https://api6.ipify.org)
ipv4addr=$(curl -s https://api.ipify.org)
curl -s "https://www.duckdns.org/update?domains=$domain&token=$token&ip=$ipv4addr&ipv6=$ipv6addr"
EOT
chmod +x /root/.ddns/duck.sh
tee /etc/systemd/system/ddns.service > /dev/null <<'EOT'
[Unit]
Description=DynDNS Updater services
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=/root/.ddns/duck.sh
[Install]
WantedBy=multi-user.target
EOT
echo
read -p "Enter the token from duckdns.org: " token
sed -i "s/enter_token/$token/g" /root/.ddns/duck.sh
read -p "Enter the domain from duckdns.org: " domain
sed -i "s/enter_domain/$domain/g" /root/.ddns/duck.sh
systemctl enable ddns
systemctl start ddns
cat <(crontab -l) <(echo "0 */2 * * * /root/.ddns/duck.sh") | crontab -
sed -i 's/\#auth/auth/g' /etc/nginx/sites-available/default
nginx -s reload
wget https://github.com/ctonton/homeserver/raw/main/scripts/http_users.sh -O /root/http_users.sh
chmod +x /root/http_users.sh
rm $0
bash /root/http_users.sh
exit
