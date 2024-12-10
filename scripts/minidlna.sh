#!/bin/bash

#minidlna
echo
echo "Setting up minidlna"
[[ -f /etc/minidlna.bak ]] || mv /etc/minidlna.conf /etc/minidlna.bak
cat >/etc/minidlna.conf <<EOT
media_dir=V,/srv/NAS/Public/Movies
media_dir=V,/srv/NAS/Public/Television
db_dir=/var/cache/minidlna
log_dir=/var/log/minidlna
log_level=off
port=8200
inotify=yes
EOT
systemctl enable minidlna
exit
