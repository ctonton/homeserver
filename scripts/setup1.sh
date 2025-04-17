#!/bin/bash

#storage
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
clear; lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
echo; echo
PS3="Select the partition to use as storage: "
select part in $(lsblk -l -o TYPE,NAME | awk '/part/ {print $2}'); do break; done
if grep -q /dev/$part /proc/mounts; then
  clear; echo "WARNING. The selected block device is already mounted to $(grep $part /proc/mounts | cut -d" " -f2)."
  echo "If you wish to continue the instalation without adding storage, type the word \"continue\"."
  read -p ":" cont
  [[ $cont != "continue" ]] && exit 1
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

#install
apt full-upgrade -y --fix-missing
apt install -y --no-install-recommends avahi-autoipd avahi-daemon bleachbit nfs-kernel-server nginx qbittorrent-nox rsync samba wsdd

#rsync
tee /etc/rsyncd.conf <<EOF
[Public]
  path = /srv/NAS/Public
  comment = Public Directory
  read only = false
EOF

#cron
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
echo "0 4 * * 1 /root/.update.sh &>/dev/null" | crontab -

#nfs
[[ -f /etc/exports.bak ]] || mv /etc/exports /etc/exports.bak
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check,insecure)" > /etc/exports
tee /etc/avahi/services/nfs.service <<EOF
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
EOF

#samba
[[ -f /etc/samba/smb.bak ]] || mv /etc/samba/smb.conf /etc/samba/smb.bak
tee /etc/samba/smb.conf <<EOF
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
EOF

#filebrowser
tag="$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep 'tag_name' | cut -d '"' -f4)"
arc="$(dpkg --print-architecture)"
[[ $arc == "armhf" ]] && arc="armv7"
wget -q --show-progress "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-$arc-filebrowser.tar.gz" -O /root/filebrowser.tar.gz
tar -xzf /root/filebrowser.tar.gz -C /usr/local/bin filebrowser
chmod +x /usr/local/bin/filebrowser
rm /root/filemanager.tar.gz
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
echo; echo "*** Legal Notice ***"
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
rm -rf /var/www/html/*
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/files/icons.zip -O /root/icons.zip
unzip -o -q /root/icons.zip -d /var/www/html
rm /root/icons.zip
[[ -f /etc/nginx/sites-available/default.bak ]] || mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
tee /var/www/html/index.html <<EOF
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
EOF
chmod -R 774 /var/www/html
chown -R www-data:www-data /var/www/html

#nginx
[[ -f /etc/nginx/nginx.bak ]] || cp /etc/nginx/nginx.conf /etc/nginx/nginx.bak
sed -i '/sendfile/d;/ssl_/d;s/access_log.*/access_log off\;/;s/gzip on/gzip off/' /etc/nginx/nginx.conf
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
		sendfile on;
		sendfile_max_chunk 1m;
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

#cleanup
apt -y autopurge
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm -f /root/.bash_profile
reboot
exit 0
