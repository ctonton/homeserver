#!/bin/bash

#install
echo
echo "Installing server."
apt full-upgrade -y --fix-missing
apt install -y --no-install-recommends curl ntfs-3g exfat-fuse tar unzip gzip nfs-kernel-server samba avahi-daemon avahi-autoipd qbittorrent-nox nginx openssl
echo "Installing wsdd."
wget -q --show-progress https://raw.githubusercontent.com/christgau/wsdd/master/src/wsdd.py -O /usr/local/bin/wsdd
chmod +x /usr/local/bin/wsdd
tee /etc/systemd/system/wsdd.service > /dev/null <<EOT
[Unit]
Description=Web Services Dynamic Discovery host daemon
After=network-online.target
Wants=network-online.target
[Service]
Type=exec
ExecStart=/usr/local/bin/wsdd -s -4
[Install]
WantedBy=multi-user.target
EOT
systemctl -q enable wsdd
echo "Installing ngrok."
case $(dpkg --print-architecture) in
  armhf)
    wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz -O /root/ngrok.tgz;;
  arm64)
    wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz -O /root/ngrok.tgz;;
  amd64)
    wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -O /root/ngrok.tgz;;
esac
tar xvf ngrok.tgz -C /usr/local/bin
rm /root/ngrok.tgz
echo "0 4 * * 1 /sbin/reboot" | crontab -

#storage
echo
echo "Mounting storage."
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | cut -d " " -f 2 > list
echo "other" >> list
echo
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
echo
echo
PS3="Select the partition to use as storage: "
select part in $(<list)
do
if [[ -b /dev/$part ]] && ! grep -q /dev/$part /proc/mounts
then
  echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
  mount -a
  mkdir -p /srv/NAS/Public
else
  sed -i '/^#UUID/d' /etc/fstab
  echo "#UUID=???  /srv/NAS  ???  defaults,nofail  0  0" >> /etc/fstab
  echo "Device is not available. Manually edit fstab later."
  read -n 1 -s -r -p "Press any key to continue without mounting storage."
fi
break
done
rm list
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/fixpermi.sh -O /root/fixpermi.sh
chmod +x /root/fixpermi.sh

#nfs
echo
echo "Setting up NFS."
if [[ ! -f /etc/exports.bak ]]
then
  mv /etc/exports /etc/exports.bak
fi
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" > /etc/exports

#samba
echo
echo "Setting up SAMBA."
if [[ ! -f /etc/samba/smb.bak ]]
then
  mv /etc/samba/smb.conf /etc/samba/smb.bak
fi
tee /etc/samba/smb.conf > /dev/null <<EOT
[global]
   workgroup = WORKGROUP
   netbios name = $HOSTNAME
   log level = 0
   server role = standalone server
   map to guest = Bad User
[Public]
   comment = Public
   path = /srv/NAS/Public
   guest ok = yes
   browsable = yes
   read only = no
   create mask = 0777
   directory mask = 0777
EOT

#ngrok
echo
read -p "Do you want to set up access to this server through ngrok? y/n: " cont
if [[ $cont == "y" ]]
then
  read -p "Enter your ngrok Authtoken: " auth
  ngrok config add-authtoken $auth
  tee -a /root/.config/ngrok/ngrok.yml > /dev/null <<EOT
tunnels:
  nginx:
    addr: 443
    proto: http
    schemes:
      - https
    inspect: false
  ssh:
    addr: 22
    proto: tcp
EOT
  ngrok service install --config /root/.config/ngrok/ngrok.yml
else
  wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/ngrok.sh -O /root/ngrok.sh
  chmod +x /root/ngrok.sh
fi

#qbittorrent
echo
echo "Setting up qBittorrent."
echo
echo "*** Legal Notice ***"
echo "qBittorrent is a file sharing program. When you run a torrent, its data will be made available to others by means of upload. Any content you share is your sole responsibility."
echo "No further notices will be issued."
read -n 1 -s -r -p "Press any key to accept and continue..."
mkdir -p /root/.config/qBittorrent
wget -q --show-progress https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
tee /root/.config/qBittorrent/qBittorrent.conf > /dev/null <<EOT
[AutoRun]
enabled=true
program=chown -R nobody:nogroup \"%R\"

[BitTorrent]
Session\GlobalMaxSeedingMinutes=1

[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Bittorrent\MaxRatioAction=1
Connection\GlobalUPLimit=10
Downloads\SavePath=/srv/NAS/Public/Downloads/
Downloads\TempPath=/srv/NAS/Public/Downloads/
IPFilter\Enabled=true
IPFilter\File=/root/.config/qBittorrent/blocklist.p2p
IPFilter\FilterTracker=true
Queueing\MaxActiveDownloads=2
Queueing\MaxActiveTorrents=3
Queueing\MaxActiveUploads=1
Queueing\QueueingEnabled=true
WebUI\AuthSubnetWhitelist=0.0.0.0/0
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=true
WebUI\LocalHostAuth=false
EOT
tee /etc/systemd/system/qbittorrent.service > /dev/null <<'EOT'
[Unit]
Description=qBittorrent Command Line Client
After=network-online.target
Wants=network-online.target
[Service]
Type=forking
User=root
Group=root
UMask=000
ExecStart=/usr/bin/qbittorrent-nox -d
[Install]
WantedBy=multi-user.target
EOT
systemctl enable qbittorrent
tee /root/.config/qBittorrent/updatelist.sh > /dev/null <<EOT
#!/bin/bash
wget -q --show-progress https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
systemctl restart qbittorrent
exit
EOT
chmod +x /root/.config/qBittorrent/updatelist.sh
cat <(crontab -l) <(echo "30 4 * * 1 /root/.config/qBittorrent/updatelist.sh") | crontab -

#nginx
echo
echo "Setting up NGINX."
if [[ ! -f /var/www/html/index.bak ]]
then
  mv /var/www/html/index* /var/www/html/index.bak
fi
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/icons.zip -O /root/icons.zip
unzip -o /root/icons.zip -d /var/www/html
rm /root/icons.zip
if [[ ! -f /etc/nginx/sites-available/default.bak ]]
then
  mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
fi
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
  <a href="/files/"><img src="fs.png" alt="HTTP Server"></a>
  <h1>File Server</h1>   
  <br>
  <br>
  <a href="/torrents/"><img src="qb.png" alt="Qbittorrent"></a>
  <h1>Torrent Server</h1>
  <br>
  <br>
</body>
</html>
EOT
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html
ln -s /srv/NAS/Public /var/www/html/files
tee /etc/nginx/sites-available/default > /dev/null <<'EOT'
##
map $http_upgrade $connection_upgrade {
	default upgrade;
	''      close;
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
	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
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

	location /files/ {
		try_files $uri $uri/ =404;
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
sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/scripts/http_users.sh -O /root/http_users.sh
chmod +x /root/http_users.sh
echo
echo "A script called http_users.sh has been created in the root directory for modifying users of the web server."
echo
echo "Add a user for the web server now."
loo="y"
until [[ $loo != "y" ]]
do
  read -p "Enter a user name: " use
  echo -n "${use}:" >> /etc/nginx/.htpasswd
  openssl passwd -apr1 >> /etc/nginx/.htpasswd
  read -p "Add another user? (y/n): " loo
done
curl -s ipinfo.io | tr -d ' ' | tr -d '"' | tr -d ',' > ipinfo
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt << ANSWERS
$(cat ipinfo | grep "country" | cut -d ':' -f 2)
$(cat ipinfo | grep "region" | cut -d ':' -f 2)
$(cat ipinfo | grep "city" | cut -d ':' -f 2)
NA
NA
localhost
admin@localhost
ANSWERS
rm ipinfo
wget -q --show-progress https://ssl-config.mozilla.org/ffdhe4096.txt -O /etc/nginx/dhparam.pem

#ufw
echo
echo "Setting up firewall."
ufw allow ssh
ufw allow http
ufw allow https
ufw allow from $(/sbin/ip route | awk '/kernel/ { print $1 }')
ufw logging off
ufw --force enable

#cleanup
apt -y autopurge
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/.bash_profile
rm $0
systemctl reboot
exit
