#!/bin/bash
apt update
apt -y install certbot
read -p 'Enter domain without the "www." prefix: ' dom
wom="www.$dom"
certbot certonly --webroot -w /var/www/html -d $wom -d $dom --register-unsafely-without-email --agree-tos
sed -i 's/ssl_certificate/#ssl_certificate/g' /etc/nginx/sites-available/default
sed -i "s/#ssl_certificate_key.*/&\n\tssl_certificate_key \/etc\/letsencrypt\/live\/$wom\/privkey.pem\;/" /etc/nginx/sites-available/default
sed -i "s/#ssl_certificate_key.*/&\n\tssl_certificate \/etc\/letsencrypt\/live\/$wom\/fullchain.pem\;/" /etc/nginx/sites-available/default
service nginx restart
exit 0
