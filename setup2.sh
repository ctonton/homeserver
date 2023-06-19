#!/bin/bash

#checks
clear
if [ $EUID -ne 0 ]
then
  read -n 1 -s -r -p "Run as "root" user. Press any key to exit."
  exit
fi
if [ $(lsb_release -is) != "Debian" ]
then
  read -n 1 -s -r -p "This script is written for the Debian OS. Press any key to exit."
  exit
fi
if ! wget -q --spider http://google.com
then
  read -n 1 -s -r -p "The network is not online. Press any key to exit."
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
apt install -y openssh-server
sed -i '0,/.*PermitRootLogin.*/s//PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable ssh
echo "0 4 * * 1 /sbin/reboot" | crontab -
cp $0 /root/resume.sh
sed -i '2,43d' /root/resume.sh
chmod +x /root/resume.sh
echo "bash /root/resume.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
systemctl enable NetworkManager-wait-online.service
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" to continue."
rm $0
reboot

rm /root/.bash_profile

#install
clear
echo "Installing software."
apt-get install -y --install-recommends firefox-esr ntfs-3g curl tar unzip gzip ufw nfs-kernel-server samba cups printer-driver-hpcups qbittorrent-nox nginx-extras php-fpm openssl tigervnc-standalone-server novnc jwm
ufw allow from $(/sbin/ip route | awk '/src/ { print $1 }')
ufw logging off
ufw enable

#storage
clear
echo "Mounting storage."
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
lsblk -l -o TYPE,NAME > list
sed -i '/disk/d' list
sed -i '1d' list
sed -i 's/[^ ]* //' list
echo "other" >> list
clear
lsblk -o NAME,TYPE,SIZE,LABEL
echo
echo
PS3="Select the partition to use as storage: "
select part in $(<list)
do
if [ -b /dev/$part ] && ! grep -q /dev/$part /proc/mounts
then
  echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,x-systemd.before=nfs-kernel-server.service,nofail  0  0" >> /etc/fstab
  mount -a
  mkdir -p /srv/NAS/Public
else
  echo "#UUID=?  /srv/NAS  ?  defaults,x-systemd.before=nfs-kernel-server.service,nofail  0  0" >> /etc/fstab
  echo "Device is not available. Manually edit fstab later."
  read -n 1 -s -r -p "Press any key to continue without mounting storage."
fi
break
done
rm list

#nfs
echo
echo "Setting up NFS."
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" >> /etc/exports

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
curl -LJ https://raw.githubusercontent.com/christgau/wsdd/master/src/wsdd.py -o /usr/local/bin/wsdd
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
systemctl enable wsdd

#cups
echo
echo "Setting up CUPS."
usermod -aG lpadmin root
lpstat -e > list
echo
echo "Enter the number for the default printer."
select defpr in $(<list)
do
lpadmin -d $defpr
break
done
rm list
cupsctl --remote-admin --no-share-printers --user-cancel-any

#ngrok
echo
read -p "Do you want to set up access to this server through ngrok? y/n: " cont
if [ $cont == "y" ]
then
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
After=network-online.target
Wants=network-online.target
[Service]
Type=exec
ExecStart=/usr/local/bin/ngrok start --all
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
IgnoreSIGPIPE=true
Restart=always
RestartSec=120
[Install]
WantedBy=multi-user.target
EOT
  read -p "Enter your ngrok Authtoken: " auth
  sed -i "s/noauth/$auth/g" /root/.ngrok2/ngrok.yml
  systemctl enable ngrok
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
tee /root/.config/qBittorrent/lanchk.sh > /dev/null <<'EOT'
#!/bin/bash
if /sbin/ip route | grep "default"
then
  OLD=$(cat /root/.config/qBittorrent/qBittorrent.conf | grep "AuthSubnetWhitelist=" | cut -d '=' -f 2 | cut -d '/' -f 1)
  NEW=$(/sbin/ip route | awk '/src/ { print $1 }' | cut -d '/' -f 1)
  if [ $OLD != $NEW ]
  then
    sed -i "s/$OLD/$NEW/g" /root/.config/qBittorrent/qBittorrent.conf
  fi
fi
exit
EOT
chmod +x /root/.config/qBittorrent/lanchk.sh
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
ExecStartPre=/root/.config/qBittorrent/lanchk.sh
ExecStart=/usr/bin/qbittorrent-nox -d
[Install]
WantedBy=multi-user.target
EOT
systemctl enable qbittorrent
tee /root/.config/qBittorrent/updatelist.sh > /dev/null <<EOT
#!/bin/bash
curl -LJ https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -o /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
systemctl restart qbittorrent
exit
EOT
chmod +x /root/.config/qBittorrent/updatelist.sh
cat <(crontab -l) <(echo "30 4 * * 1 /root/.config/qBittorrent/updatelist.sh") | crontab -

#firefox
echo
echo "Setting up Firefox."
mkdir /root/Downloads
mkdir /root/.vnc
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
while [ $ecode -eq 0 ]
do
  DISPLAY=:1 firefox
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
        <a href="/novnc/vnc.html?path=novnc/websockify"><img src="ff.png" alt="Firefox"></a>
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
tee /var/www/html/print/.user.ini > /dev/null <<'EOT'
upload_max_filesize = 10M
post_max_size = 10M
EOT
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html
tee /etc/nginx/sites-available/default > /dev/null <<'EOT'
##
map $http_upgrade $connection_upgrade {
	default upgrade;
	''      close;
}
upstream novnc-firefox {
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
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
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
		proxy_pass http://novnc-firefox/;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}

	location /novnc/websockify {
		proxy_pass http://novnc-firefox/;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
		auth_basic "Restricted Content";
		auth_basic_user_file /etc/nginx/.htpasswd;
	}
}
EOT
sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
sed -i '/http {/a\\tclient_max_body_size 10M;\n\tupload_progress uploads 1m;' /etc/nginx/nginx.conf
tee /root/webusers.sh > /dev/null <<'EOT'
#!/bin/bash
clear
loo=0
until [ $loo -eq 4 ]
do
  echo
  echo "1 - List users"
  echo "2 - Add user"
  echo "3 - Remove user"
  echo "4 - quit"
  echo
  read -p "Enter selection: :" loo
  if [ $loo -eq 1 ]
  then
    echo
    cat /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -eq 2 ]
  then
    read -p "Enter a user name: " use
    echo -n "${use}:" >> /etc/nginx/.htpasswd
    openssl passwd -apr1 >> /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -eq 3 ]
  then
    read -p "Enter a user name to remove: " use
    sed -i "/$use/d" /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -ne 0 ]
  then
    echo "Invalid selection."
    echo
  fi
done
exit
EOT
chmod +x /root/webusers.sh
echo
echo "A script called webusers.sh has been created in the root directory for modifying users of the web server."
echo
echo "Add a user for the web server now."
loo="y"
until [ $loo != "y" ]
do
  read -p "Enter a user name: " use
  echo -n "${use}:" >> /etc/nginx/.htpasswd
  openssl passwd -apr1 >> /etc/nginx/.htpasswd
  read -p "Add another user? (y/n): " loo
done
echo
echo "Answer the following questions to generate a private SSL key for the web server."
echo
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt
curl https://ssl-config.mozilla.org/ffdhe4096.txt > /etc/nginx/dhparam.pem
ufw allow 80/tcp
ufw allow 443/tcp

#wireguard
#echo
#read -p "Do you want to install and set up Wireguard? (y/n): " cont
#if [ $cont == "y" ]
#then
#  echo "Downloading WireGuard setup script to the root directory."
#  curl -LJ https://github.com/Nyr/wireguard-install/raw/master/wireguard-install.sh -o /root/setup-wireguard.sh
#  chmod +x /root/setup-wireguard.sh
#  bash /root/setup-wireguard.sh
#  ufw allow from 10.7.0.0/24
#  ufw allow 51820/udp
#  sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
#  sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
#  sed -i '/^WebUI\\AuthSubnetWhitelist=/ s/$/,10.7.0.0\/24/' /root/.config/qBittorrent/qBittorrent.conf
#else
#  tee /root/install-wireguard.sh > /dev/null <<'EOT'
##!/bin/bash
#clear
#echo "Downloading WireGuard setup script to the root directory."
#curl -LJ https://github.com/Nyr/wireguard-install/raw/master/wireguard-install.sh -o /root/setup-wireguard.sh
#chmod +x /root/setup-wireguard.sh
#bash /root/setup-wireguard.sh
#ufw allow from 10.7.0.0/24
#ufw allow 51820/udp
#sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
#sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
#sed -i '/^WebUI\\AuthSubnetWhitelist=/ s/$/,10.7.0.0\/24/' /root/.config/qBittorrent/qBittorrent.conf
#rm $0
#exit
#EOT
#  chmod +x /root/install-wireguard.sh
#fi

#cleanup
apt-get -y autoremove
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/resume.sh
reboot
