#!/bin/bash

#checks
clear
if [ $EUID -ne 0 ]
then
  read -n 1 -s -r -p "Run as "root" user. Press any key to exit."
  exit
fi
if [[ $(lsb_release -is) != @(Debian|Ubuntu|Linuxmint) ]]
then
  read -n 1 -s -r -p "This script only works with Debian, Ubuntu, or Linuxmint distrobutions. Press any key to exit."
  exit
fi
echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1
if [ $? -ne 0 ]
then
  read -n 1 -s -r -p "Network is not online. Press any key to exit."
  exit
fi
echo "This server needs to have a static IP addresses on the local network."
echo "An account at ngrok.com and authtoken are required to setup remote access to this server."
read -p "Are you ready to proceed with the installation? (y/n): " cont
if [ $cont != "y" ]
then
  exit
fi

#initialize
read -p "Enter a hostname for this server. : " serv
hostnamectl set-hostname $serv
sed -i "s/$HOSTNAME/$serv/g" /etc/hosts
dpkg-reconfigure locales
dpkg-reconfigure tzdata
apt-get update
apt-get full-upgrade -y --fix-missing
apt-get install -y --no-install-recommends openssh-server
sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable ssh
echo "0 4 * * 1 /sbin/reboot" | crontab -
cp $0 /root/resume.sh
sed -i '2,50d' /root/resume.sh
chmod +x /root/resume.sh
echo "bash /root/resume.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" through ssh to continue."
rm $0
reboot

rm /root/.bash_profile

#install
clear
echo "Installing software."
apt-get install -y --no-install-recommends ntfs-3g curl tar unzip gzip nfs-kernel-server samba avahi-daemon qbittorrent-nox nginx openssl

#storage
clear
echo "Mounting storage."
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
blkid
echo
read -p "Enter disk partition (ex. sda2): " part
uniq=$(blkid -o value -s UUID /dev/${part})
type=$(blkid -o value -s TYPE /dev/${part})
tee -a /etc/fstab > /dev/null <<EOT
UUID=${uniq}  /srv/NAS  ${type}  defaults,x-systemd.before=nfs-kernel-server.service,nofail  0  0
EOT
mount -a

#nfs
echo
echo "Setting up NFS."
tee -a /etc/exports > /dev/null <<EOT
/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check)
EOT

#samba
echo
echo "Setting up SAMBA."
if [ ! -f /etc/samba/smb.bak ]
then
  mv /etc/samba/smb.conf /etc/samba/smb.bak
fi
tee /etc/samba/smb.conf > /dev/null <<EOT
[global]
   workgroup = WORKGROUP
   netbios name = $HOSTNAME
   log level = 0
   server role = standalone server
   map to guest = bad user
[Public]
   comment = Public
   path = /srv/NAS/Public
   guest ok = yes
   browsable = yes
   read only = no
   create mask = 0777
   directory mask = 0777
EOT
curl -LJ https://raw.githubusercontent.com/christgau/wsdd/master/src/wsdd.py -o /usr/bin/wsdd
chmod +x /usr/bin/wsdd
tee /etc/systemd/system/wsdd.service > /dev/null <<EOT
[Unit]
Description=Web Services Dynamic Discovery host daemon
After=network-online.target
Wants=network-online.target
[Service]
Type=exec
ExecStart=/usr/bin/wsdd -s -4
[Install]
WantedBy=multi-user.target
EOT
systemctl enable wsdd

#ngrok
echo
echo "Installing ngrok."
if [ $(dpkg --print-architecture) = "armhf" ]
then
  curl https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.tgz -o ngrok.tgz
elif [ $(dpkg --print-architecture) = "i386" ]
then
  curl https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.tgz -o ngrok.tgz
elif [ $(dpkg --print-architecture) = "arm64" ]
then
  curl https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm64.tgz -o ngrok.tgz
elif [ $(dpkg --print-architecture) = "amd64" ]
then
  curl https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.tgz -o ngrok.tgz
fi
tar xvf ngrok.tgz -C /usr/local/bin
rm ngrok.tgz
mkdir /root/.ngrok2
tee /root/.ngrok2/ngrok.yml > /dev/null <<EOT
authtoken: noauth
tunnels:
  nginx:
    addr: 443
    proto: http
    bind_tls: true
    inspect: false
  ssh:
    addr: 22
    proto: tcp
    inspect: false
EOT
tee /etc/systemd/system/ngrok.service > /dev/null <<'EOT'
[Unit]
Description=ngrok
After=network.target
[Service]
Type=exec
ExecStart=/usr/local/bin/ngrok start --all
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
IgnoreSIGPIPE=true
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOT
read -p "Do you want to set up access to this server through ngrok? y/n: " cont
if [ $cont == "y" ]
then
  read -p "Enter your ngrok Authtoken: " auth
  sed -i "s/noauth/$auth/g" /root/.ngrok2/ngrok.yml
  systemctl enable ngrok
else
  tee /root/setup-ngrok.sh > /dev/null <<'EOT'
#!/bin/bash
clear
read -p "Enter your ngrok Authtoken: " auth
sed -i "s/noauth/$auth/g" /root/.ngrok2/ngrok.yml
systemctl enable ngrok
systemctl start ngrok
rm $0
exit
EOT
  chmod +x /root/setup-ngrok.sh
fi

#qbittorrent
echo
echo "Setting up qBittorrent."
echo
echo "*** Legal Notice ***"
echo "qBittorrent is a file sharing program. When you run a torrent, its data will be made available to others by means of upload. Any content you share is your sole responsibility."
echo
echo "No further notices will be issued."
echo
read -n 1 -s -r -p "Press any key to accept and continue..."
mkdir -p /root/.config/qBittorrent
curl -LJ https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -o /root/.config/qBittorrent/blocklist.p2p.gz
gzip -d /root/.config/qBittorrent/blocklist.p2p.gz
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
Downloads\SavePath=/srv/NAS/Public/Unsorted/
Downloads\TempPath=/srv/NAS/Public/Unsorted/
IPFilter\Enabled=true
IPFilter\File=/root/.config/qBittorrent/blocklist.p2p
IPFilter\FilterTracker=true
Queueing\MaxActiveDownloads=2
Queueing\MaxActiveTorrents=3
Queueing\MaxActiveUploads=1
Queueing\QueueingEnabled=true
WebUI\AuthSubnetWhitelist=$(/sbin/ip route | awk '/src/ { print $1 }')
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=true
WebUI\LocalHostAuth=false
EOT
tee /etc/systemd/system/qbittorrent.service > /dev/null <<'EOT'
[Unit]
Description=qBittorrent Command Line Client
After=network.target
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
systemctl start qbittorrent
tee /root/.config/qBittorrent/updatelist.sh > /dev/null <<EOT
#!/bin/bash
curl -LJ https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -o /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
systemctl restart qbittorrent
exit
EOT
chmod +x /root/.config/qBittorrent/updatelist.sh
cat <(crontab -l) <(echo "30 4 * * 1 /root/.config/qBittorrent/updatelist.sh") | crontab -

#nginx
echo
echo "Setting up NGINX."
if [ ! -f /var/www/html/index.bak ]
then
  mv /var/www/html/index* /var/www/html/index.bak
fi
curl -LJO https://github.com/ctonton/homeserver/raw/main/icons.zip
unzip -o icons.zip -d /var/www/html
rm icons.zip
ln -s /srv/NAS/Public /var/www/html/files
mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
tee /var/www/html/index.html > /dev/null <<'EOT'
<html>
  <head>
    <title>Server</title>
	  <style></style>
  </head>
  <body style="background-color:#000000;color:yellow;font-size:125%;text-align:center">
    <h1>File Server</h1>
    <a href="/files/"><img src="fs.png" alt="HTTP Server"></a>
    <br>
    <br>
    <h1>Torrent Server</h1>
    <a href="/torrents/"><img src="qb.png" alt="Qbittorrent"></a>
    <br>
    <br>
  </body>
</html>
EOT
chown -R www-data:www-data /var/www/html
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
curl -LJ https://raw.githubusercontent.com/ctonton/homeserver/main/individual_scripts/webusers.sh -o /root/webusers.sh
chmod +x /root/webusers.sh
echo
echo "A script called webusers.sh has been added the root directory for modifying users of the web server."
echo "Add a user for the web server now."
loo="y"
until [ $loo != "y" ]
do
  read -p "Enter a user name: " use
  echo -n "${use}:" >> /etc/nginx/.htpasswd
  openssl passwd -apr1 >> /etc/nginx/.htpasswd
  read -p "Add another user? (y/n): " loo
done
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt
curl https://ssl-config.mozilla.org/ffdhe4096.txt > /etc/nginx/dhparam.pem

#cleanup
apt-get autoremove
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/resume.sh
reboot
