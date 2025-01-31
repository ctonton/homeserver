#!/bin/bash

#storage
echo
echo "Mounting storage."
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
echo
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
echo
echo
PS3="Select the partition to use as storage: "
select part in $(lsblk -l -o TYPE,NAME | awk '/part/ {print $2}'); do break; done
if [[ -b /dev/$part ]] && ! grep -q /dev/$part /proc/mount
then
  echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
  mount -a
  mkdir -p /srv/NAS/Public
else
  echo "No storage mounted. Aborting server installation."
  echo "Attatch storage to device and reboot to continue."
  exit 1
fi

#install
echo
echo "Installing server."
apt full-upgrade -y --fix-missing
apt install -y --no-install-recommends avahi-autoipd avahi-daemon curl gzip minidlna nfs-kernel-server nginx ntfs-3g openssl qbittorrent-nox rsync samba tar unzip wsdd xfsprogs
tag="$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep 'tag_name' | cut -d '"' -f4)"
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
cat >/etc/systemd/system/filebrowser.service <<EOT
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
cat >/etc/rsyncd.conf <<EOT
[Public]
  path = /srv/NAS/Public
  comment = Public Directory
  read only = false
EOT
cat >/root/fixpermi.sh <<EOT
#!/bin/bash
chmod -R 777 /srv/NAS/Public
chown -R nobody:nogroup /srv/NAS/Public
exit
EOT
chmod +x /root/fixpermi.sh

#nfs
echo
echo "Setting up NFS."
[[ -f /etc/exports.bak ]] || mv /etc/exports /etc/exports.bak
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" > /etc/exports
cat >/etc/avahi/services/nfs.service <<EOT
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">NFS server at $HOSTNAME</name>  
  <service>
    <type>_nfs._tcp</type>
    <port>2049</port>
    <txt-record>path=/srv/NAS/Public</txt-record>
  </service>
</service-group>
EOT

#samba
echo
echo "Setting up SAMBA."
[[ -f /etc/samba/smb.bak ]] || mv /etc/samba/smb.conf /etc/samba/smb.bak
cat >/etc/samba/smb.conf <<EOT
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

#minidlna
echo
echo "Setting up minidlna"
[[ -f /etc/minidlna.bak ]] || mv /etc/minidlna.conf /etc/minidlna.bak
cat >/etc/minidlna.conf <<EOT
media_dir=V,/srv/NAS/Public/Movies
media_dir=V,/srv/NAS/Public/Television
db_dir=/var/cache/minidlna
log_dir=/var/log/minidlna
log_level=off
port=8200
inotify=yes
EOT
systemctl enable minidlna

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
cat >/root/.config/qBittorrent/qBittorrent.conf <<EOT
[AutoRun]
enabled=true
program=chown -R nobody:nogroup \"%R\"

[BitTorrent]
Session\AnonymousModeEnabled=true
Session\DefaultSavePath=/srv/NAS/Public/Downloads/
Session\GlobalMaxSeedingMinutes=1
Session\GlobalUPSpeedLimit=10
Session\IPFilter=/root/.config/qBittorrent/blocklist.p2p
Session\IPFilteringEnabled=true
Session\MaxActiveDownloads=2
Session\MaxActiveTorrents=3
Session\MaxActiveUploads=1
Session\MaxRatioAction=1
Session\QueueingSystemEnabled=true
Session\TempPath=/srv/NAS/Public/Downloads/
Session\TrackerFilteringEnabled=true

[LegalNotice]
Accepted=true

[Preferences]
WebUI\AuthSubnetWhitelist=0.0.0.0/0
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=true
WebUI\LocalHostAuth=false
EOT
cat >/etc/systemd/system/qbittorrent.service <<'EOT'
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

#nginx
echo
echo "Setting up NGINX."
rm -rf /var/www/html/*
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/icons.zip -O /root/icons.zip
unzip -o -q /root/icons.zip -d /var/www/html
rm /root/icons.zip
[[ -f /etc/nginx/sites-available/default.bak ]] || mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
cat >/var/www/html/index.html <<EOT
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
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html
cat >/etc/nginx/sites-available/default <<'EOT'
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

	location /filebrowser {
		proxy_pass http://filebrowser;
  		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}
}
EOT
sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
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

#cron
cat >/root/.update.sh <<EOT
#/bin/bash
wget -q --show-progress https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
apt update
apt -y upgrade
apt -y autopurge
reboot
EOT
echo "0 4 * * 1 /root/.update.sh &>/dev/null" | crontab -

#cleanup
apt -y autopurge
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/.bash_profile
systemctl reboot
exit 0
