#!/bin/bash
echo "Setting up qBittorrent."
apt-get install -y --no-install-recommends curl unzip qbittorrent-nox
mkdir -p /root/.config/qBittorrent
curl -LJO https://github.com/ctonton/homeserver/raw/main/blocklist.zip
unzip -o blocklist.zip -d /root/.config/qBittorrent
rm blocklist.zip
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
exit
