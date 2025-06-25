#!/bin/bash

#name="$HOSTNAME"
#lang="en_US.UTF-8 UTF-8"
#zone="America/Chicago"
#part="auto"
#acpt="true"

#function
finish () {
  rm -f "$0"
  reboot
  exit 0
}

#online
while : ; do
  wget -q --spider https://deb.debian.org && break
  sleep 5
done

#initialize
systemctl -f --now disable unattended-upgrades
apt update
(dpkg -l locales | grep -q 'ii') || apt install -y locales
until [ ! -z "$name" ] ; do
  echo ; echo
  read -p "Enter a hostname for this device :" name
done
hostnamectl set-hostname "$name"
name=$(hostname)
sed -i "s/$HOSTNAME/$name/g" /etc/hosts
if [ -z "$lang" ] ; then
  dpkg-reconfigure locales
else
  grep -q -x "$lang" /usr/share/i18n/SUPPORTED || exit 1
  [ -f /etc/locale.gen.bak ] || mv /etc/locale.gen /etc/locale.gen.bak
  echo "$lang" > /etc/locale.gen
  dpkg-reconfigure --frontend=noninteractive locales
fi
if [ -z "$zone" ] ; then
  dpkg-reconfigure tzdata
else
  [ -f /usr/share/zoneinfo/"$zone" ] || exit 1
  ln -f -s /usr/share/zoneinfo/"$zone" /etc/localtime
  dpkg-reconfigure --frontend=noninteractive tzdata
fi
ramm=$(awk '/MemTotal/ {print $2 / 1000000}' /proc/meminfo) && ramm=${ramm%.*}

#install
apt full-upgrade -y --fix-missing
pkg=(avahi-autoipd avahi-daemon bleachbit cron curl exfat-fuse gzip locales nano nfs-kernel-server nginx ntfs-3g openssh-server qbittorrent-nox rsync samba tar tzdata unzip wsdd2 xfsprogs)
[[ $ramm -ge 1 ]] && pkg+=(cups-browsed ffmpeg firefox-esr jwm nginx-extras nmap novnc openssl php-fpm printer-driver-hpcups shellinabox sudo tigervnc-standalone-server)
apt install -y ${pkg[@]}

#storage
umount -f -q /srv/NAS
sed -i "/\/srv\/NAS/d" /etc/fstab
mkdir -p /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
if [ -z $part ] ; then
  echo ; echo
  lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
  echo
  PS3="Select the partition to use as storage: "
  select part in $(lsblk -l -o TYPE,NAME | awk '/part/ {print $2}') none ; do break ; done
fi
[ $part == "auto" ] && part=$(blkid | grep "xfs" | cut -d \: -f 1)
[ $part == "none" ] || echo "UUID=$(blkid -o value -s UUID ${part})  /srv/NAS  $(blkid -o value -s TYPE ${part})  defaults,nofail  0  0" >> /etc/fstab
systemctl daemon-reload
mount -a
mkdir -p /srv/NAS/Public/Downloads
chmod -R 777 /srv/NAS/Public
chown -R nobody:nogroup /srv/NAS/Public
tee /root/fixpermi.sh << EOF
#!/bin/bash
chmod -R 777 /srv/NAS/Public
chown -R nobody:nogroup /srv/NAS/Public
exit
EOF
chmod +x /root/fixpermi.sh

#rsync
tee /etc/rsyncd.conf << EOF
[Public]
  path = /srv/NAS/Public
  comment = Public Directory
  read only = false
EOF

#update
f="$(grep -l 'APT::Periodic' /etc/apt/apt.conf.d/* | head -n 1)"
grep -q 'Periodic::Enable' "$f" || sed -i '1s/^/APT::Periodic::Enable "0";\n/' "$f"
grep 'APT::Periodic' "$f" | cut -d " " -f 1 > /dev/shm/list
cat /dev/shm/list | while read l ; do sed -i "s~$l.*~$l \"0\"\;~" "$f" ; done
rm -f /dev/shm/list
tee /root/.update.sh << EOF
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
crontab -l | grep -q '.update.sh' || echo '0 4 * * 1 /root/.update.sh &> /dev/null' | crontab -

#nfs
[ -f /etc/exports.bak ] || mv /etc/exports /etc/exports.bak
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" > /etc/exports
tee /etc/avahi/services/nfs.service << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">NFS server at $name</name>  
  <service>
    <type>_nfs._tcp</type>
    <port>2049</port>
    <txt-record>path=/srv/NAS/Public</txt-record>
  </service>
</service-group>
EOF

#samba
[ -f /etc/samba/smb.conf.bak ] || mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
tee /etc/samba/smb.conf << EOF
[global]
   workgroup = WORKGROUP
   netbios name = $name
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
tag=$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep 'tag_name' | cut -d \" -f 4)
arc=$(dpkg --print-architecture)
[ $arc == "armhf" ] && arc="armv7"
wget -q --show-progress https://github.com/filebrowser/filebrowser/releases/download/${tag}/linux-${arc}-filebrowser.tar.gz -O /root/filebrowser.tar.gz
tar -xzf /root/filebrowser.tar.gz -C /usr/local/bin filebrowser
chmod +x /usr/local/bin/filebrowser
rm /root/filebrowser.tar.gz
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/filebrowser.zip -O /root/filebrowser.zip
mkdir -p /root/.config
unzip -o /root/filebrowser.zip -d /root/.config/
rm /root/filebrowser.zip
tee /etc/systemd/system/filebrowser.service << EOF
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
if [ $acpt != "true" ] ; then
  echo ; echo
  echo "*** Legal Notice ***"
  echo "qBittorrent is a file sharing program. When you run a torrent, its data will be made available to others by means of upload. Any content you share is your sole responsibility."
  echo "No further notices will be issued."
  read -n 1 -s -r -p "Press any key to accept and continue..."
fi
mkdir -p /root/.config/qBittorrent
wget -q --show-progress https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
tee /root/.config/qBittorrent/qBittorrent.conf << EOF
[Application]
FileLogger\Age=1
FileLogger\AgeType=1
FileLogger\Backup=true
FileLogger\DeleteOld=true
FileLogger\Enabled=false
FileLogger\MaxSizeBytes=66560
FileLogger\Path=/root/.local/share/qBittorrent/logs

[AutoRun]
enabled=true
program=chown -R nobody:nogroup \"%R\"

[BitTorrent]
Session\AddTorrentStopped=false
Session\AnonymousModeEnabled=true
Session\DefaultSavePath=/srv/NAS/Public/Downloads/
Session\ExcludedFileNames=
Session\GlobalMaxInactiveSeedingMinutes=1
Session\GlobalMaxSeedingMinutes=1
Session\GlobalUPSpeedLimit=10
Session\IPFilter=/root/.config/qBittorrent/blocklist.p2p
Session\IPFilteringEnabled=true
Session\IgnoreSlowTorrentsForQueueing=true
Session\MaxActiveDownloads=3
Session\MaxActiveTorrents=3
Session\MaxActiveUploads=1
Session\MaxConnections=300
Session\MaxUploads=12
Session\QueueingSystemEnabled=true
Session\ShareLimitAction=Remove
Session\TempPath=/srv/NAS/Public/Downloads/
Session\TrackerFilteringEnabled=true

[Core]
AutoDeleteAddedTorrentFile=IfAdded

[LegalNotice]
Accepted=true

[Meta]
MigrationVersion=8

[Network]

[Preferences]
General\Locale=en
MailNotification\req_auth=true
WebUI\AuthSubnetWhitelist=0.0.0.0/0
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\CSRFProtection=false
WebUI\ClickjackingProtection=true
WebUI\LocalHostAuth=false
EOF
tee /etc/systemd/system/qbittorrent.service << EOF
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
[ -f /etc/nginx/sites-available/default.bak ] || mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
tee /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>$name</title>
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
[ -f /etc/nginx/nginx.conf.bak ] && cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf || cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
sed -i 's/^\tssl_/\t#ssl_/;s/gzip on/gzip off/;s/access_log.*/access_log off\;/' /etc/nginx/nginx.conf
tee /etc/nginx/sites-available/default > /dev/null << EOF

upstream filebrowser {
	server 127.0.0.1:8000;
}

server {
	listen 80 default_server;
	root /var/www/html;
	index index.html;

	location /filebrowser {
		proxy_pass http://filebrowser;
		proxy_buffering off;

	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
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

#quit
[[ $ramm -ge 1 ]] || finish

#shell
sed -i 's/--no-beep/--no-beep --disable-ssl/' /etc/default/shellinabox

#firefox
[ -d /root/Downloads ] || ln -s /srv/NAS/Public/Downloads /root/Downloads
tee /root/.ignite.sh << 'EOF'
#!/bin/bash
while : ; do
  DISPLAY=:1 firefox -private-window || break
done
EOF
chmod +x /root/.ignite.sh

#jwm
tee /root/.jwmrc << EOF
<?xml version="1.0"?>
<JWM>
    <Group>
        <Option>maximized</Option>
        <Option>noborder</Option>
    </Group>
    <WindowStyle>
        <Font>Sans-9:bold</Font>
        <Width>1</Width>
        <Height>1</Height>
        <Corner>0</Corner>
        <Foreground>#FFFFFF</Foreground>
        <Background>#FFFFFF</Background>
        <Outline>#FFFFFF</Outline>
        <Opacity>1.0</Opacity>
        <Active>
            <Foreground>#FFFFFF</Foreground>
            <Background>#FFFFFF</Background>
            <Outline>#FFFFFF</Outline>
            <Opacity>1.0</Opacity>
        </Active>
    </WindowStyle>
    <IconPath>/usr/share/icons</IconPath>
    <IconPath>/usr/share/pixmaps</IconPath>
    <IconPath>/usr/local/share/jwm</IconPath>
    <Desktops width="1" height="1">
        <Background type="solid">#FFFFFF</Background>
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
tee /root/.vnc/xstartup << EOF
#!/bin/bash
websockify -D --web=/usr/share/novnc/ 5800 127.0.0.1:5901
/usr/bin/jwm
EOF
chmod +x /root/.vnc/xstartup
tee /etc/systemd/system/tigervnc.service << EOF
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
defpr=$(lpstat -e | head -n 1)
lpadmin -d $defpr
cupsctl --no-share-printers

#php
grep -q 'serv.sh' /etc/sudoers || echo 'www-data ALL=(root) NOPASSWD: /var/www/php/serv.sh' >> /etc/sudoers
grep -q 'rout.sh' /etc/sudoers || echo 'www-data ALL=(root) NOPASSWD: /var/www/php/rout.sh' >> /etc/sudoers
rm -rf /var/www/php
mkdir /var/www/php
tee /var/www/php/list.sh << 'EOF'
#!/bin/bash
nmap -sn -oG /dev/shm/list $(ip route | awk '/kernel/ {print $1}') > /dev/null
sed -e '/#/d ; s/^Host\: //g ; s/).*/)\n/g' /dev/shm/list
rm /dev/shm/list
exit 0
EOF
tee /var/www/php/rout.sh << 'EOF'
#!/bin/bash
ssh -o StrictHostKeyChecking=no root@$(ip route | awk '/default/{print$3}') 'reboot &'
exit 0
EOF
tee /var/www/php/serv.sh << 'EOF'
#!/bin/bash
systemctl reboot
exit 0
EOF
chmod -R 774 /var/www/php
chown -R www-data:www-data /var/www/php

#html
tee /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>$name</title>
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
      <a href="/novnc/vnc.html?autoconnect=true&resize=remote"><img src="images/fox.png" alt="Firefox"></a>
      <h1>Browser</h1>
      <br>
      <br>
      <a href="/list/"><img src="images/net.png" alt="Network"></a>
      <h1>Network</h1>
      <br>
      <br>
      <a href="/reset/"><img src="images/rst.png" alt="Reboot"></a>
      <h1>Reboot</h1>
      <br>
      <br>
      <a href="/torrents/"><img src="images/qbt.png" alt="Qbittorrent"></a>
      <h1>Torrents</h1>
      <br>
      <br>
    </div>
    <div class="column">
      <br>
      <br>
      <a href="/filebrowser"><img src="images/fbr.png" alt="File Browser"></a>
      <h1>Files</h1>
      <br>
      <br>
      <a href="/print/"><img src="images/prn.png" alt="Print Server"></a>
      <h1>Print</h1>
      <br>
      <br>
      <a href="/shell/"><img src="images/tml.png" alt="Terminal"></a>
      <h1>Terminal</h1>
      <br>
      <br>
    </div>
  </div>
</body>
</html>
EOF
mkdir -p /var/www/html/print
tee /var/www/html/print/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Print PDF</title>
  <style>
    body {
      font-family: Arial, sans-serif;
      margin: 20px;
    }
    label {
      margin-top: 10px;
    }
    input, select {
      padding: 5px;
      margin-top: 5px;
      width: 100%;
    }
    button {
      padding: 10px;
      background-color: #4CAF50;
      color: white;
      border: none;
      cursor: pointer;
      width: 100%;
    }
    button:hover {
      background-color: #45a049;
    }
  </style>
</head>
<body>
  <h1>Print PDF on Network Printer</h1>
  <form action="print.php" method="POST" enctype="multipart/form-data">
    <p>
      <label for="printer">Select Printer:</label>
      <select name="printer" id="printer" required></select>
    </p>
    <p>
      <label for="pdf">Upload PDF:</label>
      <input type="file" name="pdf" accept=".pdf" required></input>
    </p>
    <h3>Print options:</h3>
    <label for="copies">Number of Copies:</label>
    <input type="number" name="copies" value="1" min="1"></input><br><br>
    <label for="duplex">Duplex (Default Single-sided):</label>
    <input type="checkbox" name="duplex" value="DuplexNoTumble"></input><br><br>
    <label for="color">Black & White (Default Color):</label>
    <input type="checkbox" name="color" value="Gray"></input><br><br>
    <label for="scale">No Scaling (Default Auto):</label>
    <input type="checkbox" name="scale" value="none"></input><br><br>
    <button type="submit">Print PDF</button>
  </form>
  <script>
    fetch('printers.php')
    .then(response => response.json())
    .then(data => {
      const printerSelect = document.getElementById('printer');
      data.printers.forEach(printer => {
        let option = document.createElement('option');
        option.value = printer;
        option.textContent = printer;
        printerSelect.appendChild(option);
      });
    })
    .catch(error => console.error('Error fetching printers:', error));
  </script>
</body>
</html>

EOF
tee /var/www/html/print/print.php << 'EOF'
<?php
  if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    $printer = $_POST['printer'];
    $file = $_FILES['pdf']['tmp_name'];
    $file_name = $_FILES['pdf']['name'];
    $file_size = $_FILES['pdf']['size'];
    $copies = isset($_POST['copies']) ? (int)$_POST['copies'] : 1;
    $color = isset($_POST['color']) ? '-o ColorModel=Gray' : '';
    $duplex = isset($_POST['duplex']) ? '-o Duplex=DuplexNoTumble' : '';
    $scale = isset($_POST['scale']) ? '-o print-scaling=none' : '';
    $ready = shell_exec("lpstat -a $printer");

    if (mime_content_type($file) != 'application/pdf') {
      echo "Error: Please upload a valid PDF file.";
      exit;
    }
    if ($file_size > 10485760){
      echo "Error: Maximum PDF size is 10MB, choose a smaller file.";
      exit;
    }

    if (str_contains($ready, 'accepting')) {
      exec("lp -d $printer -n $copies $color $duplex $scale $file");
      echo "$file_name sent to $printer.";
    }
    else {
      echo "Error: Selected printer is not available.";
    }
  }
?>
EOF
tee /var/www/html/print/printers.php << 'EOF'
<?php
  $printers = shell_exec("lpstat -p"); 
  $printers = explode("\n", trim($printers));
  $printerNames = [];

  foreach ($printers as $printer) {
    if (preg_match('/^printer (\S+)/', $printer, $matches)) {
      $printerNames[] = $matches[1];
    }
  }

  echo json_encode(['printers' => $printerNames]);
?>
EOF
tee /var/www/html/print/.user.ini << 'EOF'
upload_max_filesize = 10M
post_max_size = 10M
EOF
mkdir /var/www/html/list
tee /var/www/html/list/index.php << 'EOF'
<?php
  $output = shell_exec('/bin/bash /var/www/php/list.sh');
  echo "<pre><font size='5pt'>$output</font></pre>";
?>
EOF
mkdir /var/www/html/reset
tee /var/www/html/reset/index.html << 'EOF'
<!DOCTYPE html>
<html>
<body>
  <h1>Are you sure that you want to restart the network?</h1>
  <form method="post" action="reboot.php">
    <p><button style="border-radius: 8px; width: 64px;" onclick="history.back()">No</button></p>
    <p><input style="border-radius: 8px; width: 64px;" type="submit" class="button" name="serV" value="Server"></input></p>
    <p><input style="border-radius: 8px; width: 64px;" type="submit" class="button" name="rouT" value="Router"></input></p>
    <p><input style="border-radius: 8px; width: 64px;" type="submit" class="button" name="botH" value="Both"></input></p>
  </form>
</body>
</html>
EOF
tee /var/www/html/reset/reboot.php << 'EOF'
<?php
  if(isset($_POST["serV"])) {
    echo "Server rebooting.";
    exec("sudo /var/www/php/serv.sh");
  }
  if(isset($_POST["rouT"])) {
    echo "Router rebooting.";
    exec("sudo /var/www/php/rout.sh");
  }
  if(isset($_POST["botH"])) {
    echo "Network rebooting.";
    exec("sudo /var/www/php/rout.sh");
    exec("sudo /var/www/php/serv.sh");
  }
?>
EOF
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html

#nginx
grep -q 'client_max_body_size' /etc/nginx/nginx.conf || sed -i 's/server_tokens.*/&\n\tclient_max_body_size 10M\;\n\tupload_progress uploads 1m\;/' /etc/nginx/nginx.conf
tee /etc/nginx/sites-available/default << 'EOF'

map $http_upgrade $connection_upgrade {
	default upgrade;
	'' close;
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
	listen 443 ssl;
	listen [::]:443 ssl;
	http2 on;
	ssl_certificate /etc/nginx/nginx-selfsigned.crt;
	ssl_certificate_key /etc/nginx/nginx-selfsigned.key;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_ecdh_curve X25519:prime256v1:secp384r1;
	ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
	ssl_prefer_server_ciphers off;
	ssl_session_timeout 1d;
	ssl_session_cache shared:SSL:10m;
	ssl_dhparam /etc/nginx/dhparam.pem;
	add_header Strict-Transport-Security "max-age=63072000" always;
	add_header X-Frame-Options SAMEORIGIN;
	add_header X-Content-Type-Options nosniff;
	add_header X-XSS-Protection "1; mode=block";
	root /var/www/html;
	index index.html index.php;
	#auth_basic "Restricted Content";
	#auth_basic_user_file /etc/nginx/.htpasswd;

	location = /robots.txt {
		add_header Content-Type text/plain;
		return 200 "User-agent: *\nDisallow: /\n";
	}

	location /Public {
		alias /srv/NAS/Public;
		autoindex on;
		dav_methods PUT DELETE MKCOL COPY MOVE;
		dav_ext_methods PROPFIND OPTIONS LOCK UNLOCK;
		dav_access user:rw group:rw all:rw;
		client_body_temp_path /srv/NAS/Public/Downloads;
		client_max_body_size 0;
		create_full_put_path on;
	}

	location /filebrowser {
		proxy_pass http://filebrowser;
		proxy_buffering off;
	}

	location /torrents/ {
		proxy_pass http://127.0.0.1:8080/;
		proxy_buffering off;
	}

	location /shell/ {
		proxy_pass http://127.0.0.1:4200/;
		proxy_buffering off;
	}

	location /print/print.php {
		include /etc/nginx/fastcgi_params;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_index print.php;
		fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
		fastcgi_intercept_errors on;
		track_uploads uploads 300s;
	}

	location /print/printers.php {
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:/run/php/php-fpm.sock;
	}

	location /list/index.php {
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:/run/php/php-fpm.sock;
	}

	location /reset/reboot.php {
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:/run/php/php-fpm.sock;
	}

	location /novnc/ {
		proxy_pass http://127.0.0.1:5800/;
		proxy_buffering off;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection $connection_upgrade;
		proxy_set_header Host $host;
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
tee /root/http_users.sh << 'EOF'
#!/bin/bash
clear
echo "Manage HTTP users"
opt=0
until [[ $opt -eq 4 ]] ; do
  echo
  echo "1 - Add user"
  echo "2 - Remove user"
  echo "3 - List users"
  echo "4 - Quit"
  echo
  read -p "Enter selection: " opt
  case $opt in
    1)
      read -p "Enter a user name: " use
      if [ -f /etc/nginx/.htpasswd ] ; then
        echo -n "${use}:" >> /etc/nginx/.htpasswd
        openssl passwd -apr1 >> /etc/nginx/.htpasswd
      else
        echo -n "${use}:" > /etc/nginx/.htpasswd
        openssl passwd -apr1 >> /etc/nginx/.htpasswd
        sed -i 's/#auth_basic/auth_basic/g' /etc/nginx/sites-available/default
        systemctl restart nginx
      fi
      clear
      echo "$use added"
      ;;
    2)
      if [ -f /etc/nginx/.htpasswd ] ; then
        PS3="Enter a number: "
        select use in $(cat /etc/nginx/.htpasswd | cut -d ':' -f 1) ; do
          sed -i "/$use/d" /etc/nginx/.htpasswd
          break
        done
        if [ -z "$(cat ${file_name})" ] ; then
          rm /etc/nginx/.htpasswd
          sed -i 's/auth_basic/#auth_basic/g' /etc/nginx/sites-available/default
          systemctl restart nginx
        fi
        clear
        echo "$use removed"
      else
        clear
        echo "No users exist."
      fi
      ;;
    3)
      if [ -f /etc/nginx/.htpasswd ]; then
        clear
        cat /etc/nginx/.htpasswd | cut -d ':' -f 1
      else
        clear
        echo "No users exist."
      fi
      ;;
    *)
      clear
      echo "Invalid selection"
      ;;
  esac
done
exit
EOF
chmod +x /root/http_users.sh
[ -f /etc/nginx/.htpasswd ] && sed -i 's/#auth_basic/auth_basic/g' /etc/nginx/sites-available/default

#ssl
curl -s ipinfo.io | tr -d ',; ;"' > /dev/shm/ipinfo
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout /etc/nginx/nginx-selfsigned.key -out /etc/nginx/nginx-selfsigned.crt << ANSWERS
$(grep "country" /dev/shm/ipinfo | cut -d \: -f 2)
$(grep "region" /dev/shm/ipinfo | cut -d \: -f 2)
$(grep "city" /dev/shm/ipinfo | cut -d \: -f 2)
NA
NA
localhost
admin@localhost
ANSWERS
rm -f /dev/shm/ipinfo
wget -q --show-progress https://ssl-config.mozilla.org/ffdhe4096.txt -O /etc/nginx/dhparam.pem
if [ -d /etc/letsencrypt/live/www* ] ; then
  wom=$(ls /etc/letsencrypt/live | grep 'www')
  sed -i 's/ssl_certificate/#ssl_certificate/g' /etc/nginx/sites-available/default
  sed -i "s/#ssl_certificate_key.*/&\n\tssl_certificate_key \/etc\/letsencrypt\/live\/${wom}\/privkey.pem\;/" /etc/nginx/sites-available/default
  sed -i "s/#ssl_certificate_key.*/&\n\tssl_certificate \/etc\/letsencrypt\/live\/${wom}\/fullchain.pem\;/" /etc/nginx/sites-available/default
fi

#exit
finish
