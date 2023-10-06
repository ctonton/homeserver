#!/bin/bash
apt update
apt upgrade
tag="$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep -o '"tag_name": ".*"' | sed 's/"//g' | sed 's/tag_name: //g')"
case $(dpkg --print-architecture) in
  armhf)
    wget -q --show-progress "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-armv7-filebrowser.tar.gz" -O /root/filemanager.tar.gz;;
  arm64)
    wget -q --show-progress "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-arm64-filebrowser.tar.gz" -O /root/filemanager.tar.gz;;
  amd64)
    wget -q --show-progress "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-amd64-filebrowser.tar.gz" -O /root/filemanager.tar.gz;;
esac
tar -xzf /root/filemanager.tar.gz -C /usr/local/bin filebrowser
chmod +x /usr/local/bin/filebrowser
rm /root/filemanager.tar.gz
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/filebrowser.zip -O /root/filebrowser.zip
mkdir -p /root/.config
unzip -o /root/filebrowser.zip -d /root/.config/
rm /root/filebrowser.zip
tee /etc/systemd/system/filebrowser.service > /dev/null <<EOT
[Unit]
Description=http file manager
After=network-online.target
Wants=network-online.target
[Service]
Type=exec
ExecStart=/usr/local/bin/filebrowser -c /root/.config/filebrowser/filebrowser.json -d /root/.config/filebrowser/filebrowser.db
[Install]
WantedBy=multi-user.target
EOT
systemctl -q enable filebrowser
tee /var/www/html/index.html > /dev/null <<EOT
<!DOCTYPE html>
<html>
<head>
  <title>$HOSTNAME</title>
  <meta charset="UTF-8">
</head>
<body style="background-color:#F3F3F3;font-family:arial;text-align:center">
  <br>
  <br>
  <a href="/filebrowser"><img src="fs.png" alt="File Browser"></a>
  <h1>File Browser</h1>
  <br>
  <br>
  <a href="/torrents/"><img src="qb.png" alt="Qbittorrent"></a>
  <h1>Torrent Server</h1>
  <br>
  <br>
</body>
</html>
EOT
unlink /var/www/html/files
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html
tee /etc/nginx/sites-available/default > /dev/null <<'EOT'
##
map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
}
upstream filebrowser {
        server 127.0.0.1:8000;
}
##
server {
listen 80 default_server;
listen [::]:80 default_server;
        location / {
        return 301 https://$host$request_uri;
        }
}
##
server {
        listen 443 ssl http2;
        listen [::]:443 ssl http2;
        ssl_certificate /etc/nginx/nginx-selfsigned.crt;
        ssl_certificate_key /etc/nginx/nginx-selfsigned.key;
        ssl_session_timeout  10m;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off;
        ssl_dhparam /etc/nginx/dhparam.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GC>
        ssl_prefer_server_ciphers off;
        resolver 8.8.8.8 8.8.4.4 valid=300s;
        resolver_timeout 5s;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        client_max_body_size 10M;
        root /var/www/html;
        index index.html;
        autoindex on;

        location /filebrowser {
                proxy_pass http://filebrowser;
                auth_basic "Restricted Content";
                auth_basic_user_file /etc/nginx/.htpasswd;
        }
        location /torrents/ {
                proxy_pass http://127.0.0.1:8080/;
                proxy_buffering off;
                auth_basic "Restricted Content";
                auth_basic_user_file /etc/nginx/.htpasswd;
        }
}
EOT
systemctl reboot
exit
