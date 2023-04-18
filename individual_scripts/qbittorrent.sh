#!/bin/bash
echo "Setting up qBittorrent."
apt-get install -y --no-install-recommends curl gzip qbittorrent-nox
echo
echo "*** Legal Notice ***"
echo "qBittorrent is a file sharing program. When you run a torrent, its data will be made available to others by means of upload. Any content you share is your sole responsibility."
echo
echo"No further notices will be issued."
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
exit
