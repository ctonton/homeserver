#!/bin/bash
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
After=network.target
[Service]
Type=exec
ExecStart=/usr/local/bin/ngrok start --all
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
IgnoreSIGPIPE=true
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOT
read -p "Enter your ngrok Authtoken: " auth
sed -i "s/noauth/$auth/g" /root/.ngrok2/ngrok.yml
systemctl enable ngrok
systemctl start ngrok
exit
