#!/bin/bash
echo "Setting up SAMBA."
apt-get install -y --no-install-recommends samba
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
systemctl restart smbd
curl -LJ https://raw.githubusercontent.com/christgau/wsdd/master/src/wsdd.py -o /usr/bin/wsdd
chmod +x /usr/bin/wsdd
tee /etc/systemd/system/wsdd.service > /dev/null <<'EOT'
[Unit]
Description=Web Services Dynamic Discovery host daemon
After=network-online.target
Wants=network-online.target
[Service]
Type=exec
ExecStart=/usr/bin/wsdd -s -4
[Install]
WantedBy=multi-user.target
EOT
systemctl enable wsdd
systemctl start wsdd
exit
