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
echo "This server needs a static IP addresses on the local network."
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
apt-get install -y --no-install-recommends openssh-server
apt-get full-upgrade -y --fix-missing
sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
echo "0 4 * * 1 /sbin/reboot" | crontab -
cp $0 /root/resume.sh
sed -i '2,49d' /root/resume.sh
chmod +x /root/resume.sh
echo "bash /root/resume.sh" > /root/.bash_profile
chmod +x /root/.bash_profile
echo
read -n 1 -s -r -p "System needs to reboot. Press any key to do so and then log in as "root" through ssh to continue."
rm $0
reboot

#install
clear
echo "Installing software."
apt-get install -y --no-install-recommends ntfs-3g curl tar unzip nfs-kernel-server samba avahi-daemon qbittorrent-nox

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
Type=simple
ExecStart=/usr/bin/wsdd -s -4
[Install]
WantedBy=multi-user.target
EOT
systemctl enable wsdd

#http
echo
echo "Setting up http server"
tee /etc/systemd/system/pyhttp.service > /dev/null <<'EOT'
[Unit]
Description=python http server
After=network.target
[Service]
ExecStart=/usr/bin/python3 -m http.server -d /srv/NAS 8000
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOT
systemctl enable pyhttp

#qbittorrent
echo
echo "Setting up qBittorrent."
mkdir -p /root/.config/qBittorrent
curl -LJO https://github.com/ctonton/homeserver/raw/main/blocklist.zip
unzip -o blocklist.zip -d /root/.config/qBittorrent
rm blocklist.zip
tee /root/.config/qBittorrent/setp.sh > /dev/null <<'EOT'
#!/bin/bash
chmod -R 777 /srv/NAS/Public/Unsorted
chown -R nobody:nogroup /srv/NAS/Public/Unsorted
exit
EOT
chmod +x /root/.config/qBittorrent/setp.sh
tee /root/.config/qBittorrent/qBittorrent.conf > /dev/null <<EOT
[AutoRun]
enabled=true
program="/root/.config/qBittorrent/setp.sh"

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
UMask=777
ExecStart=/usr/bin/qbittorrent-nox -d
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOT
systemctl enable qbittorrent

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
read -p "Do you want to set up access to this server through ngrok? y/n: " cont
if [ $cont == "y" ]
then
  read -p "Enter your ngrok Authtoken: " auth
else
  auth=none
  tee /root/setup-ngrok.sh > /dev/null <<'EOT'
#!/bin/bash
clear
read -p "Enter your ngrok Authtoken: " auth
sed -i "s/none/$auth/g" /root/.ngrok2/ngrok.yml
systemctl enable ngrok
systemctl start ngrok
rm $0
exit
EOT
  chmod +x /root/setup-ngrok.sh
fi
tee /root/.ngrok2/ngrok.yml > /dev/null <<EOT
authtoken: ${auth}
tunnels:
  pyhttp:
    addr: 8000
    proto: http
    bind_tls: true
    inspect: false
  qbittorrent:
    addr: 8080
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
if [ $auth != "none" ]
then
  systemctl enable ngrok
fi

#cleanup
apt-get autoremove
rm /root/.bash_profile
read -n 1 -s -r -p "System needs to reboot. Press any key to do so."
rm /root/resume.sh
reboot
