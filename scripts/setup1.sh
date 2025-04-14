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
grep -q /dev/$part /proc/mounts && (echo "No storage mounted. Aborting server installation."; echo "Attatch storage to device and reboot to continue."; exit 1)
echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
mount -a
mkdir -p /srv/NAS/Public

#install
echo
echo "Installing server."
apt full-upgrade -y --fix-missing
apt install -y --no-install-recommends avahi-autoipd avahi-daemon bleachbit nfs-kernel-server nginx qbittorrent-nox rsync samba wsdd
tag="$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep 'tag_name' | cut -d '"' -f4)"
case $(dpkg --print-architecture) in
  armhf)
    wget -q --show-progress --inet4-only "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-armv7-filebrowser.tar.gz" -O /root/filemanager.tar.gz;;
  arm64)
    wget -q --show-progress --inet4-only "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-arm64-filebrowser.tar.gz" -O /root/filemanager.tar.gz;;
  amd64)
    wget -q --show-progress --inet4-only "https://github.com/filebrowser/filebrowser/releases/download/$tag/linux-amd64-filebrowser.tar.gz" -O /root/filemanager.tar.gz;;
esac
tar -xzf /root/filemanager.tar.gz -C /usr/local/bin filebrowser
chmod +x /usr/local/bin/filebrowser
rm /root/filemanager.tar.gz
wget -q --show-progress --inet4-only https://github.com/ctonton/homeserver/raw/main/files/filebrowser.zip -O /root/filebrowser.zip
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

#cron
cat >/root/.update.sh <<EOT
#/bin/bash
wget -q --show-progress --inet4-only https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
gzip -df /root/.config/qBittorrent/blocklist.p2p.gz
apt update
apt -y upgrade
apt -y autopurge
bleachbit -c --all-but-warning
fstrim -av
reboot
EOT
echo "0 4 * * 1 /root/.update.sh &>/dev/null" | crontab -

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

#qbittorrent
echo
echo "Setting up qBittorrent."
echo
echo "*** Legal Notice ***"
echo "qBittorrent is a file sharing program. When you run a torrent, its data will be made available to others by means of upload. Any content you share is your sole responsibility."
echo "No further notices will be issued."
read -n 1 -s -r -p "Press any key to accept and continue..."
mkdir -p /root/.config/qBittorrent
wget -q --show-progress --inet4-only https://github.com/Naunter/BT_BlockLists/raw/master/bt_blocklists.gz -O /root/.config/qBittorrent/blocklist.p2p.gz
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
wget -q --show-progress --inet4-only https://github.com/ctonton/homeserver/raw/main/files/icons.zip -O /root/icons.zip
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
	client_max_body_size 10M;
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

EOT

#cleanup
apt -y autopurge
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/.bash_profile
systemctl reboot
exit 0
