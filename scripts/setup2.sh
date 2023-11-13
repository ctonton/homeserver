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
select part in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | cut -d " " -f 2) other
do
if [[ -b /dev/$part ]] && ! grep -q /dev/$part /proc/mounts
then
  echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
  mount -a
  mkdir -p /srv/NAS/Public
else
  echo "Device is not available. Manually edit fstab later."
  read -n 1 -s -r -p "Press any key to continue without mounting storage."
fi
break
done

#install
echo
echo "Installing server."
echo "0 4 * * 1 /sbin/reboot" | crontab -
apt full-upgrade -y --fix-missing
apt install -y --no-install-recommends cups curl exfat-fuse firefox-esr gzip jwm minidlna nfs-kernel-server nginx-extras novnc ntfs-3g openssl php-fpm printer-driver-hpcups qbittorrent-nox samba tar tigervnc-standalone-server unzip wireguard-tools wsdd
apt install -y --install-recommends avahi-autoipd avahi-daemon cups-browsed
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
tee /root/fixpermi.sh > /dev/null <<'EOT'
#!/bin/bash
chmod -R 777 /srv/NAS/Public
chown -R nobody:nogroup /srv/NAS/Public
exit
EOT
chmod +x /root/fixpermi.sh

#nfs
echo
echo "Setting up NFS."
if [[ ! -f /etc/exports.bak ]]
then
  mv /etc/exports /etc/exports.bak
fi
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" > /etc/exports
tee /etc/avahi/services/nfs.service > /dev/null <<EOT
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

#minidlna
echo
echo "Setting up minidlna"
if [[ ! -f /etc/minidlna.bak ]]
then
  mv /etc/minidlna.conf /etc/minidlna.bak
fi
tee /etc/minidlna.conf > /dev/null <<EOT
media_dir=V,/srv/NAS/Public/Movies
media_dir=V,/srv/NAS/Public/Television
db_dir=/var/cache/minidlna
log_dir=/var/log/minidlna
log_level=off
port=8200
inotify=yes
EOT
systemctl enable minidlna

#cups
echo
echo "Setting up CUPS."
usermod -aG lpadmin root
echo
PS3="Enter the number for the default printer: "
select defpr in $(lpstat -e)
do
lpadmin -d $defpr
break
done
cupsctl --no-share-printers

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
if ! (crontab -l | grep -q updatelist.sh)
then
  cat <(crontab -l) <(echo "30 4 * * 1 /root/.config/qBittorrent/updatelist.sh") | crontab -
fi

#firefox
echo
echo "Setting up Firefox."
mkdir -p /root/Downloads
mkdir -p /root/.vnc
tee /root/.vnc/xstartup > /dev/null <<EOT
#!/bin/bash
/usr/bin/jwm
EOT
chmod +x /root/.vnc/xstartup
tee /root/.jwmrc > /dev/null <<EOT
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
EOT
tee /root/.ignite.sh > /dev/null <<'EOT'
#!/bin/bash
websockify -D --web=/usr/share/novnc/ 5800 127.0.0.1:5901
ecode=0
while [[ $ecode -eq 0 ]]
do
  DISPLAY=:1 firefox -private
  ecode=$?
done
EOT
chmod +x /root/.ignite.sh
tee /etc/systemd/system/tigervnc.service > /dev/null <<'EOT'
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
EOT
systemctl enable tigervnc

#nginx
echo
echo "Setting up NGINX."
rm /var/www/html/*
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/icons.zip -O /root/icons.zip
unzip -o -q /root/icons.zip -d /var/www/html
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
      <a href="/filebrowser"><img src="fs.png" alt="File Browser"></a>
      <h1>File Browser</h1>
      <br>
      <br>
      <a href="/print/"><img src="ps.png" alt="Print Server"></a>
      <h1>Print Server</h1>
      <br>
      <br>
    </div>
    <div class="column">
      <br>
      <br>
      <a href="/torrents/"><img src="qb.png" alt="Qbittorrent"></a>
      <h1>Torrent Server</h1>
      <br>
      <br>
      <a href="/novnc/vnc.html?path=novnc/websockify"><img src="ff.png" alt="Firefox"></a>
      <h1>Web Browser</h1>
      <br>
      <br>
    </div>
  </div>
  <div class="footer">
    <a href="/egg/"><img src="ee.png" alt="ee"></a>
  </div>
</body>
</html>
EOT
mkdir /var/www/html/print
tee /var/www/html/print/index.html > /dev/null <<'EOT'
<html>
<body>

<form action="print.php" method="post" enctype="multipart/form-data">
	Select PDF to print:
	<input type="file" name="fileToUpload" id="fileToUpload">
	<input type="submit" value="Upload PDF" name="submit">
</form>

</body>
</html>
EOT
tee /var/www/html/print/print.php > /dev/null <<'EOT'
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
EOT
tee /var/www/html/print/.user.ini > /dev/null <<'EOT'
upload_max_filesize = 10M
post_max_size = 10M
EOT
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html
ln -s /root/Downloads /var/www/html/egg
tee /etc/nginx/sites-available/default > /dev/null <<'EOT'
##
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

	location /egg/ {
		try_files $uri $uri/ =404;
	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /print/ {
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /print/print.php {
		include /etc/nginx/fastcgi_params;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_index print.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		track_uploads uploads 300s;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /novnc/ {
		proxy_pass http://novnc-firefox/;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /novnc/websockify {
		proxy_pass http://novnc-firefox/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
		#auth_basic "Restricted Content";
		#auth_basic_user_file /etc/nginx/.htpasswd;
	}
}
EOT
sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
sed -i '/http {/a\\tclient_max_body_size 10M;\n\tupload_progress uploads 1m;' /etc/nginx/nginx.conf
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

#cleanup
apt -y autopurge
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/.bash_profile
rm $0
systemctl reboot
exit
