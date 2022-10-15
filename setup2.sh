#!/bin/bash

clear
if [ $EUID -ne 0 ]
then
  read -n 1 -s -r -p "Please run as "root". Press any key to exit."
  exit
fi
if [ $(dpkg --print-architecture) != "armhf" ]
then
  read -n 1 -s -r -p "This script works on ARM devices only. Press any key to exit."
  exit
fi
echo -e "GET http://google.com HTTP/1.0\n\n" | nc google.com 80 > /dev/null 2>&1
if [ $? -ne 0 ]
then
  read -n 1 -s -r -p "Network is not online. Press any key to exit."
  exit
fi
echo "This server and the default printer need to be have static IP addresses on the local network and this server should either be added to the demilitarized zone or have ports forwarded in the router."
read -p "Do you wish to continue? (y/n): " cont
if [ ${cont} != "y" ]
then
  exit
fi

#install
echo "Installing software."
apt update
apt install -y ntfs-3g samba nfs-kernel-server cups php-fpm nginx-extras qbittorrent-nox curl tar unzip ufw openssl tigervnc-standalone-server novnc
apt install -y --no-install-recommends jwm

#storage
clear
echo "Mounting storage."
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
blkid
echo
read -p "Enter disk partition (ex. sda1): " device
uniq=$(blkid -o value -s UUID /dev/${device})
type=$(blkid -o value -s TYPE /dev/${device})
tee -a /etc/fstab > /dev/null <<EOT
UUID=${uniq}  /srv/NAS  ${type}  defaults,nofail,uid=65534,gid=65534  0  0
EOT
mount -a

#nfs
echo
echo "Setting up NFS."
tee -a /etc/exports > /dev/null <<EOT
/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check)
EOT
systemctl restart nfs-kernel-server

#samba
echo
echo "Setting up SAMBA."
if [ ! -f /etc/samba/smb.bak ]
then
  mv /etc/samba/smb.conf /etc/samba/smb.bak
fi
tee /etc/samba/smb.conf > /dev/null <<'EOT'
[global]
   workgroup = WORKGROUP
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
systemctl restart smbd

#cups
echo
echo "Setting up print server."
usermod -aG lpadmin root
cupsctl --remote-admin --user-cancel-any
read -p "Enter the static IP address of the default printer. (ex. 10.10.10.11): " defip
subip=${defip%.*}
read -p "Enter a name for the default printer: " defpr
lpadmin -p $defpr -E -v ipp://${defip}/ipp/print -m everywhere
lpadmin -d $defpr
systemctl restart cups

#ngrok
echo
echo "Setting up ngrok."
curl https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.tgz -o ngrok-stable-linux-arm.tgz
tar xvf ngrok-stable-linux-arm.tgz -C /usr/local/bin
rm ngrok-stable-linux-arm.tgz
mkdir /root/.ngrok2
read -p "Enter your ngrok Authtoken: " auth
tee /root/.ngrok2/ngrok.yml > /dev/null <<EOT
authtoken: ${auth}
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
ExecStart=/usr/local/bin/ngrok start --all
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
IgnoreSIGPIPE=true
Restart=always
RestartSec=3
Type=simple
[Install]
WantedBy=multi-user.target
EOT
systemctl enable ngrok
systemctl start ngrok

#ddns
echo
echo "Setting up Duck DNS."
mkdir /root/.ddns
read -p "Enter the token from duckdns.org: " token
read -p "Enter the domain from duckdns.org: " domain
tee /root/.ddns/duck.sh > /dev/null <<EOT
#!/bin/bash
domain=${domain}
token=${token}
ipv6addr=$(curl -s https://api6.ipify.org)
ipv4addr=$(curl -s https://api.ipify.org)
curl -s "https://www.duckdns.org/update?domains=$domain&token=$token&ip=$ipv4addr&ipv6=$ipv6addr"
EOT
chmod +x /root/.ddns/duck.sh
tee /etc/systemd/system/ddns.service > /dev/null <<'EOT'
[Unit]
Description=DynDNS Updater services
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
ExecStart=/root/.ddns/duck.sh
[Install]
WantedBy=multi-user.target
EOT
systemctl enable ddns
systemctl start ddns

#qbittorrent
echo
echo "Setting up qBittorrent."
echo
echo "Accept the Legal Notice and then pres ctl+c to exit qBittorrent."
echo
qbittorrent-nox
curl -LJO https://github.com/ctonton/homeserver/raw/main/blocklist.zip
unzip -o blocklist.zip -d /root/.config/qBittorrent
rm blocklist.zip
tee /root/.config/qBittorrent/qBittorrent.conf > /dev/null <<EOT
[AutoRun]
enabled=false
program=

[BitTorrent]
Session\GlobalMaxSeedingMinutes=1

[LegalNotice]
Accepted=true

[Network]
Cookies=@Invalid()

[Preferences]
Advanced\RecheckOnCompletion=false
Advanced\trackerPort=9000
Bittorrent\MaxConnecs=255
Bittorrent\MaxRatio=0.01
Bittorrent\MaxRatioAction=1
Connection\GlobalUPLimit=50
Connection\PortRangeMin=17839
Connection\ResolvePeerCountries=true
Downloads\SavePath=/srv/NAS/Public/Unsorted/
Downloads\ScanDirsV2=@Variant(\0\0\0\x1c\0\0\0\0)
Downloads\TempPath=/srv/NAS/Public/Unsorted/
DynDNS\DomainName=changeme.dyndns.org
DynDNS\Enabled=false
DynDNS\Password=
DynDNS\Service=0
DynDNS\Username=
General\Locale=
IPFilter\Enabled=true
IPFilter\File=/root/.config/qBittorrent/blocklist.p2p
IPFilter\FilterTracker=true
MailNotification\email=
MailNotification\enabled=false
MailNotification\password=
MailNotification\req_auth=true
MailNotification\req_ssl=false
MailNotification\sender=qBittorrent_notification@example.com
MailNotification\smtp_server=smtp.changeme.com
MailNotification\username=
Queueing\MaxActiveDownloads=2
Queueing\MaxActiveTorrents=3
Queueing\MaxActiveUploads=1
Queueing\QueueingEnabled=true
WebUI\Address=*
WebUI\AlternativeUIEnabled=false
WebUI\AuthSubnetWhitelist=${subip}.0/24
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\BanDuration=3600
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=true
WebUI\CustomHTTPHeaders=
WebUI\CustomHTTPHeadersEnabled=false
WebUI\HTTPS\CertificatePath=
WebUI\HTTPS\Enabled=false
WebUI\HTTPS\KeyPath=
WebUI\HostHeaderValidation=true
WebUI\LocalHostAuth=false
WebUI\MaxAuthenticationFailCount=5
WebUI\Port=8080
WebUI\RootFolder=
WebUI\SecureCookie=true
WebUI\ServerDomains=*
WebUI\SessionTimeout=3600
WebUI\UseUPnP=true
WebUI\Username=admin
EOT
tee /etc/systemd/system/qbittorrent.service > /dev/null <<'EOT'
[Unit]
Description=qBittorrent Command Line Client
After=network.target
[Service]
Type=forking
User=root
Group=root
UMask=777
ExecStart=/usr/bin/qbittorrent-nox -d
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOT
systemctl enable qbittorrent
systemctl start qbittorrent

#firefox
echo
echo "Setting up Firefox."
mkdir /root/.vnc
tee /root/.vnc/xstartup > /dev/null <<EOT
#!/bin/bash
/usr/bin/jwm
EOT
chmox +x /root/.vnc/xstartup
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
    <IconPath>/usr/share/icons/hicolor/256x256/apps</IconPath>
    <IconPath>/usr/share/icons/hicolor/256x256/mimetypes</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/actions</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/apps</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/categories</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/devices</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/emblems</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/mimetypes</IconPath>
    <IconPath>/usr/share/icons/hicolor/32x32/status</IconPath>
    <IconPath>/usr/share/icons/hicolor/512x512/apps</IconPath>
    <IconPath>/usr/share/icons/hicolor/512x512/mimetypes</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/actions</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/apps</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/categories</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/devices</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/emblems</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/mimetypes</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/places</IconPath>
    <IconPath>/usr/share/icons/hicolor/scalable/status</IconPath>
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
    <Key key="Up">up</Key>
    <Key key="Down">down</Key>
    <Key key="Right">right</Key>
    <Key key="Left">left</Key>
    <Key key="Return">select</Key>
    <Key key="Escape">escape</Key>
    <StartupCommand>/root/.ignite.sh</StartupCommand>
</JWM>
EOT
tee /root/.ignite.sh > /dev/null <<'EOT'
#!/bin/bash
ecode=0
while [ $ecode -eq 0 ]
do
  DISPLAY=:0 firefox
  ecode=$?
done
EOT
chmox +x /root/.ignite.sh
tee /etc/systemd/system/tigervnc.service > /dev/null <<'EOT'
[Unit]
Description=Remote desktop service (VNC)
After=network.target
[Service]
Type=forking
ExecStart=/usr/bin/tigervncserver -SecurityTypes None -localhost no --I-KNOW-THIS-IS-INSECURE :0
ExecStop=/usr/bin/tigervncserver -kill :0
[Install]
WantedBy=multi-user.target
EOT
systemctl enable tigervnc
systemctl start tigervnc
tee /etc/systemd/system/websockify.service > /dev/null <<'EOT'
[Unit]
Description=novnc websockify service
After=network.target
[Service]
Type=forking
ExecStart=/usr/bin/websockify -D --web=/usr/share/novnc/ 5800 127.0.0.1:5900
ExecStop=/usr/bin/killall websockify
[Install]
WantedBy=multi-user.target
EOT
systemctl enable websockify
systemctl start websockify

#nginx
echo
echo "Setting up web server."
if [ ! -f /var/www/html/index.bak ]
then
  mv /var/www/html/index* /var/www/html/index.bak
fi
curl -LJO https://github.com/ctonton/homeserver/raw/main/icons.zip
unzip -o icons.zip -d /var/www/html
rm icons.zip
ln -s /srv/NAS/Public /var/www/html/files
ln -s /root/Downloads /var/www/html/egg
mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
tee /var/www/html/index.html > /dev/null <<'EOT'
<html>
  <head>
    <title>Server</title>
	<style>
    .column {
    float: left;
    width: 50%;
    height: 2160px;
    }
	.row:after {
    content: "";
    display: table;
    clear: both;
    }
    </style>
  </head>
  <body style="background-color:#000000;color:yellow;font-size:125%">
    <div class="row" style="text-align:center">
      <div class="column">
        <h1>File Server</h1>
        <a href="/files/"><img src="fs.png" alt="HTTP Server"></a>
        <br>
        <br>
        <h1>Print Server</h1>
        <a href="/print/"><img src="ps.png" alt="Print Server"></a>
        <br>
        <br>
      </div>
      <div class="column" style="text-align:center">
        <h1>Torrent Server</h1>
        <a href="/torrents/"><img src="qb.png" alt="Qbittorrent"></a>
        <br>
        <br>
        <h1>Web Browser</h1>
        <a href="/firefox/"><img src="ff.png" alt="Firefox"></a>
        <br>
        <br>
	  </div>
    </div>
  </body>
  <footer>
    <a href="/egg/"><img align="right" src="ee.png"></right></a>
  </footer>
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
chown -R www-data:www-data /var/www/html
tee /etc/nginx/sites-available/default > /dev/null <<'EOT'
##
map $http_upgrade $connection_upgrade {
	default upgrade;
	''      close;
}
upstream novpn-firefox {
	server 127.0.0.1:5800;
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

	location /egg/ {
		try_files $uri $uri/ =404;
	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /print/ {
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /print/print.php {
		include /etc/nginx/fastcgi_params;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_index print.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		track_uploads uploads 300s;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /novnc/ {
		proxy_pass http://novpn-firefox/;
	}

	location /novnc/websockify {
		proxy_pass http://novpn-firefox/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
	}
}
EOT
sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
sed -i '/http {/a\\tclient_max_body_size 10M;\n\tupload_progress uploads 1m;' /etc/nginx/nginx.conf
echo
echo "Add users to web server."
loo="y"
until [ ${loo} != "y" ]
do
  read -p "Enter a user name: " use
  echo -n "${use}:" >> /etc/nginx/.htpasswd
  openssl passwd -apr1 >> /etc/nginx/.htpasswd
  read -p "Add another user? (y/n): " loo
done
echo
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt
curl https://ssl-config.mozilla.org/ffdhe4096.txt > /etc/nginx/dhparam.pem
systemctl restart php*
systemctl restart nginx

#ufw
echo
echo "Setting up firewall."
ufw allow 80
ufw allow 443
ufw allow 51820/udp
ufw allow from ${subip}.0/24
ufw allow from 10.7.0.0/24
ufw enable
sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf

#wireguard
echo
echo "Downloading WireGuard script."
curl -LJ https://github.com/Nyr/wireguard-install/raw/master/wireguard-install.sh -o /root/wireguard-install.sh
read -p "Do you wish to set up WireGuard now? (y/n): " cont
if [ ${cont} != "y" ]
then
  exit
fi
bash /root/wireguard-install.sh
exit
