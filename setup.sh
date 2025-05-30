#!/bin/bash

#function
function finish {
  clear; read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
  rm -f $0
  reboot
  exit 0
}

#check
clear
[[ $EUID -eq 0 ]] || (echo "Must run as root user."; exit 1)
wget -q --spider www.google.com || (echo "The network is not online."; exit 1)
[[ $(lsb_release -is) == "Debian" ]] || (echo "This script only works on Debian Linux."; exit 1)
mem=$(awk '/MemTotal/ {print $2 / 1000000}' /proc/meminfo) && mem=${mem%.*}

#install
systemctl -q disable unattended-upgrades --now
apt update
apt full-upgrade -y --fix-missing
pkg=(avahi-autoipd avahi-daemon bleachbit cron curl exfat-fuse gzip locales nano nfs-kernel-server nginx ntfs-3g openssh-server qbittorrent-nox rsync samba tar tzdata unzip wsdd xfsprogs)
[[ $mem -ge 1 ]] && pkg+=(cups-browsed cups firefox-esr jwm nginx-extras novnc openssl php-fpm printer-driver-hpcups tigervnc-standalone-server)
apt install -y ${pkg[@]}

#initialize
clear; read -p "Enter a hostname for this server. : " hst
hostnamectl set-hostname $hst
sed -i "s/$HOSTNAME/$hst/g" /etc/hosts
dpkg-reconfigure locales
dpkg-reconfigure tzdata

#storage
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
clear; lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
echo; echo
PS3="Select the partition to use as storage: "
select part in $(lsblk -l -o TYPE,NAME | awk '/part/ {print $2}'); do break; done
if grep -q /dev/$part /proc/mounts; then
  clear; echo "WARNING. The selected block device is already mounted to: "
  grep $part /proc/mounts | cut -d" " -f2
  echo; echo "If you wish to continue the instalation without adding storage, type the word \"continue\"."
  read -p ":" cont
  [[ $cont == "continue" ]] || exit 1
else
  echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
  mount -a
fi
mkdir -p /srv/NAS/Public
chmod -R 777 /srv/NAS/Public
chown -R nobody:nogroup /srv/NAS/Public
tee /root/fixpermi.sh <<EOF
#!/bin/bash
chmod -R 777 /srv/NAS/Public
chown -R nobody:nogroup /srv/NAS/Public
exit
EOF
chmod +x /root/fixpermi.sh

#rsync
tee /etc/rsyncd.conf <<EOF
[Public]
  path = /srv/NAS/Public
  comment = Public Directory
  read only = false
EOF

#update
f="$(grep -l 'APT::Periodic' /etc/apt/apt.conf.d/* | head -n1)"
grep -q 'Periodic::Enable' "$f" || sed -i '1s/^/APT::Periodic::Enable "0";\n/' "$f"
grep 'APT::Periodic' "$f" | cut -d" " -f1 >/dev/shm/list
cat /dev/shm/list | while read l; do sed -i "s~$l.*~$l \"0\"\;~" "$f"; done
rm -f /dev/shm/list
tee /root/.update.sh <<EOF
#/bin/bash
wget -q --show-progress https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
apt update
apt -y upgrade
apt -y autopurge
bleachbit -c --all-but-warning
fstrim -av
reboot
EOF
chmod +x /root/.update.sh
echo "0 4 * * 1 /root/.update.sh &>/dev/null" | crontab -

#nfs
[[ -f /etc/exports.bak ]] || mv /etc/exports /etc/exports.bak
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" > /etc/exports
tee /etc/avahi/services/nfs.service <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">NFS server at $hst</name>  
  <service>
    <type>_nfs._tcp</type>
    <port>2049</port>
    <txt-record>path=/srv/NAS/Public</txt-record>
  </service>
</service-group>
EOF

#samba
[[ -f /etc/samba/smb.bak ]] || mv /etc/samba/smb.conf /etc/samba/smb.bak
tee /etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   netbios name = $hst
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
EOF

#filebrowser
tag="$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep 'tag_name' | cut -d '"' -f4)"
arc="$(dpkg --print-architecture)"
[[ $arc == "armhf" ]] && arc="armv7"
wget -q --show-progress "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-$arc-filebrowser.tar.gz" -O /root/filebrowser.tar.gz
tar -xzf /root/filebrowser.tar.gz -C /usr/local/bin filebrowser
chmod +x /usr/local/bin/filebrowser
rm /root/filebrowser.tar.gz
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/filebrowser.zip -O /root/filebrowser.zip
mkdir -p /root/.config
unzip -o /root/filebrowser.zip -d /root/.config/
rm /root/filebrowser.zip
tee /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=http file manager
After=network-online.target
Wants=network-online.target
[Service]
Type=exec
ExecStart=/usr/local/bin/filebrowser -c /root/.config/filebrowser/filebrowser.json -d /root/.config/filebrowser/filebrowser.db
[Install]
WantedBy=multi-user.target
EOF
systemctl -q enable filebrowser

#qbittorrent
clear; echo "*** Legal Notice ***"
echo "qBittorrent is a file sharing program. When you run a torrent, its data will be made available to others by means of upload. Any content you share is your sole responsibility."
echo "No further notices will be issued."
read -n 1 -s -r -p "Press any key to accept and continue..."
mkdir -p /root/.config/qBittorrent
wget -q --show-progress https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
tee /root/.config/qBittorrent/qBittorrent.conf <<EOF
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
EOF
tee /etc/systemd/system/qbittorrent.service <<EOF
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
EOF
systemctl enable qbittorrent

#html
rm -rf /var/www/html
mkdir -p /var/www/html/images
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/icons.zip -O /root/icons.zip
unzip -o -q /root/icons.zip -d /var/www/html/images
rm /root/icons.zip
[[ -f /etc/nginx/sites-available/default.bak ]] || mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
tee /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>$hst</title>
  <meta charset="UTF-8">
</head>
<body style="background-color:#F3F3F3;font-family:arial;text-align:center">
  <br>
  <br>
  <a href="/filebrowser"><img src="images/fbr.png" alt="File Browser"></a>
  <h1>File Browser</h1>
  <br>
  <br>
  <a href="/torrents/"><img src="images/qbt.png" alt="Qbittorrent"></a>
  <h1>Torrent Server</h1>
  <br>
  <br>
</body>
</html>
EOF
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html

#nginx
[[ -f /etc/nginx/nginx.bak ]] || cp /etc/nginx/nginx.conf /etc/nginx/nginx.bak
sed -i '/ssl_/d;s/user www-data/user root/;s/gzip on/gzip off/;s/access_log.*/access_log off\;/' /etc/nginx/nginx.conf
grep -q 'sendfile_max_chunk' /etc/nginx/nginx.conf || sed -i 's/sendfile on\;/&\n\tsendfile_max_chunk 1m\;/' /etc/nginx/nginx.conf
tee /etc/nginx/sites-available/default >/dev/null <<'EOF'

upstream filebrowser {
	server 127.0.0.1:8000;
}

server {
	listen 80 default_server;
	listen [::]:80 default_server;
	root /var/www/html;
	index index.html;

	location /Public {
		alias /srv/NAS/Public;
		autoindex on;
  	}

	location /filebrowser {
		proxy_pass http://filebrowser;
	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
	}
}
EOF

#quit
[[ $mem -ge 1 ]] || finish

#firefox
mkdir -p /root/Downloads
tee /root/.ignite.sh <<'EOF'
#!/bin/bash
websockify -D --web=/usr/share/novnc/ 5800 127.0.0.1:5901
ecode=0
while [[ $ecode -eq 0 ]]; do
  DISPLAY=:1 firefox -private-window &>/dev/null
  ecode=$?
done
EOF
chmod +x /root/.ignite.sh

tee /root/.jwmrc <<EOF
<?xml version="1.0"?>
<JWM>
    <Group>
        <Option>maximized</Option>
        <Option>noborder</Option>
    </Group>
    <WindowStyle>
        <Font>Sans-9:bold</Font>
        <Width>4</Width>
        <Height>21</Height>
        <Corner>3</Corner>
        <Foreground>#FFFFFF</Foreground>
        <Background>#555555</Background>
        <Outline>#000000</Outline>
        <Opacity>0.5</Opacity>
        <Active>
            <Foreground>#FFFFFF</Foreground>
            <Background>#0077CC</Background>
            <Outline>#000000</Outline>
            <Opacity>1.0</Opacity>
        </Active>
    </WindowStyle>
    <IconPath>/usr/share/icons</IconPath>
    <IconPath>/usr/share/pixmaps</IconPath>
    <IconPath>/usr/local/share/jwm</IconPath>
    <Desktops width="4" height="1">
        <Background type="solid">#111111</Background>
    </Desktops>
    <DoubleClickSpeed>400</DoubleClickSpeed>
    <DoubleClickDelta>2</DoubleClickDelta>
    <FocusModel>sloppy</FocusModel>
    <SnapMode distance="10">border</SnapMode>
    <MoveMode>opaque</MoveMode>
    <ResizeMode>opaque</ResizeMode>
    <StartupCommand>/root/.ignite.sh</StartupCommand>
</JWM>
EOF

#vnc
mkdir -p /root/.vnc
tee /root/.vnc/xstartup <<EOF
#!/bin/bash
/usr/bin/jwm
EOF
chmod +x /root/.vnc/xstartup
tee /etc/systemd/system/tigervnc.service <<EOF
[Unit]
Description=Remote desktop service (VNC)
After=network.target
[Service]
Type=forking
User=root
ExecStart=/usr/bin/tigervncserver -Log *:syslog:0 -localhost no -SecurityTypes None --I-KNOW-THIS-IS-INSECURE :1
ExecStop=/usr/bin/tigervncserver -kill :1
[Install]
WantedBy=multi-user.target
EOF
systemctl enable tigervnc

#cups
usermod -aG lpadmin root
if [[ $(lpstat -e | wc -w) -gt 1 ]]; then
  clear; echo
  PS3="Enter the number for the default printer: "
  [[ $acc -eq 1 ]] && defpr="$(lpstat -e | head -n1)" || (select defpr in $(lpstat -e); do break; done)
else
  defpr="$(lpstat -e)"
fi
lpadmin -d $defpr
cupsctl --no-share-printers
tee /var/www/html/print.html <<EOF
<!DOCTYPE html>
<html>
  <body>
    <form action="print.php" method="post" enctype="multipart/form-data">
      <p>Select PDF to print:  <input type="file" name="fileToUpload" id="fileToUpload"></p>
      <input type="submit" value="Upload PDF" name="submit">
    </form>
  </body>
</html>
EOF
tee /var/www/html/print.php <<'EOF'
<?php
   if(isset($_FILES['fileToUpload'])){
      $file_name = $_FILES['fileToUpload']['name'];
      $file_size =$_FILES['fileToUpload']['size'];
      $file_tmp =$_FILES['fileToUpload']['tmp_name'];
      $file_type=$_FILES['fileToUpload']['type'];
      $file_ext=strtolower(end(explode('.',$_FILES['fileToUpload']['name'])));
      $extensions= array("pdf","PDF");

      if(in_array($file_ext,$extensions)=== false){
         exit("File type not allowed, please choose a PDF file.");
      }

      if($file_size > 10485760){
         exit("Maximum PDF size is 10MB, choose a smaller file.");
      }

      exec("lp $file_tmp");
      echo "PDF sent to printer.";
   }
?>
EOF
tee /var/www/html/.user.ini <<EOF
upload_max_filesize = 10M
post_max_size = 10M
EOF

#html
tee /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>$hst</title>
  <meta charset="UTF-8">
  <style>
    body {
      background-color: #F3F3F3;
    }
    .column {
      float: left;
      width: 50%;
      text-align: center;
      font-family: arial;
      height: 2160px;
    }
    .row:after {
      content: "";
      display: table;
      clear: both;
    }
    .footer {
      text-align: right;
    }
  </style>
</head>
<body>
  <div class="row">
    <div class="column">
      <br>
      <br>
      <a href="/filebrowser"><img src="images/fbr.png" alt="File Browser"></a>
      <h1>File Browser</h1>
      <br>
      <br>
      <a href="print.html"><img src="images/prn.png" alt="Print Server"></a>
      <h1>Print Server</h1>
      <br>
      <br>
    </div>
    <div class="column">
      <br>
      <br>
      <a href="/torrents/"><img src="images/qbt.png" alt="Qbittorrent"></a>
      <h1>Torrent Server</h1>
      <br>
      <br>
      <a href="/novnc/vnc.html?path=novnc/websockify"><img src="images/fox.png" alt="Firefox"></a>
      <h1>Web Browser</h1>
      <br>
      <br>
    </div>
  </div>
  <div class="footer">
    <a href="/downloads"><img src="images/egg.png" alt="Downloads"></a>
  </div>
</body>
</html>
EOF
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html

#nginx
sed -i '/http {/a\\tclient_max_body_size 10M;\n\tupload_progress uploads 1m;' /etc/nginx/nginx.conf
tee /etc/nginx/sites-available/default <<'EOF'

map $http_upgrade $connection_upgrade {
	default upgrade;
	''      close;
}

upstream novnc-firefox {
	server 127.0.0.1:5800;
}

upstream filebrowser {
	server 127.0.0.1:8000;
}

server {
	listen 80 default_server;
	listen [::]:80 default_server;

	return 301 https://$host$request_uri;
}

server {
	listen 443 ssl http2;
	listen [::]:443 ssl http2;
	ssl_certificate /etc/nginx/nginx-selfsigned.crt;
	ssl_certificate_key /etc/nginx/nginx-selfsigned.key;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ecdh_curve X25519:prime256v1:secp384r1;
	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
	ssl_prefer_server_ciphers off;
	ssl_session_timeout 1d;
	ssl_session_cache shared:SSL:10m;
	ssl_session_tickets off;
	ssl_dhparam /etc/nginx/dhparam.pem;
	add_header Strict-Transport-Security "max-age=63072000" always;
	root /var/www/html;
	index index.html;

	location = /robots.txt {
		add_header Content-Type text/plain;
		return 200 "User-agent: *\nDisallow: /\n";
	}

	location /Public {
		alias /srv/NAS/Public;
		autoindex on;
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /filebrowser {
		proxy_pass http://filebrowser;
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location print.html {
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
  }

	location /print.php {
		include /etc/nginx/fastcgi_params;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_index print.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		track_uploads uploads 300s;
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /novnc/ {
		proxy_pass http://novnc-firefox/;
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /novnc/websockify {
		proxy_pass http://novnc-firefox/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
		satisfy any;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /downloads {
		alias /root/Downloads;
		autoindex on;
	}
}

server {
  listen 591;

  location /Public {
    alias /srv/NAS/Public;
    autoindex on;
  }
}
EOF

#ssl
curl -s ipinfo.io | tr -d ',; ;"' >/dev/shm/ipinfo
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt <<ANSWERS
$(grep "country" /dev/shm/ipinfo | cut -d: -f2)
$(grep "region" /dev/shm/ipinfo | cut -d: -f2)
$(grep "city" /dev/shm/ipinfo | cut -d: -f2)
NA
NA
localhost
admin@localhost
ANSWERS
rm -f /dev/shm/ipinfo
wget -q --show-progress https://ssl-config.mozilla.org/ffdhe4096.txt -O /etc/nginx/dhparam.pem

#exit
finish
