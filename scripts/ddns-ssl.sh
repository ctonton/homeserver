#!/bin/bash
clear ; echo "Ensure that ports 80 and 443 are open."
echo ; read -p "Enter the token from your DuckDNS account: " tok
echo ; read -p "Enter the domain from your DuckDNS account: " dom
curl "https://www.duckdns.org/update?domains=${dom}&token=${tok}&ip="
(crontab -l | sed '/duckdns/d' ; echo -e "*/15 * * * * curl \"https://www.duckdns.org/update?domains=${dom}&token=${tok}&ip=\" &> /dev/null") | crontab -
apt update
apt -y install certbot
systemctl stop nginx.service
certbot certonly --standalone -d www.${dom}.duckdns.org -d ${dom}.duckdns.org --register-unsafely-without-email --agree-tos
if [ $? != 0 ] ; then
  systemctl start nginx.service
  exit 1
fi
sed -i '/_hook/d' /etc/letsencrypt/renewal/www.${dom}.duckdns.org.conf
echo 'pre_hook = "systemctl stop nginx.service"' >> /etc/letsencrypt/renewal/www.${dom}.duckdns.org.conf
echo 'post_hook = "systemctl start nginx.service"' >> /etc/letsencrypt/renewal/www.${dom}.duckdns.org.conf
sed -i 's/^ssl_certificate/#ssl_certificate/g' /etc/nginx/sites-available/default
sed -i "s/#ssl_certificate_key.*/&\n\tssl_certificate_key \/etc\/letsencrypt\/live\/www.${dom}.duckdns.org\/privkey.pem\;/" /etc/nginx/sites-available/default
sed -i "s/#ssl_certificate_key.*/&\n\tssl_certificate \/etc\/letsencrypt\/live\/www.${dom}.duckdns.org\/fullchain.pem\;/" /etc/nginx/sites-available/default
systemctl start nginx.service
exit 0
