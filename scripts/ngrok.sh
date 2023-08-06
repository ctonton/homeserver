#!/bin/bash
clear
echo "Installing ngrok."
if [[ $(dpkg --print-architecture) = "armhf" ]]
then
  wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz -O ngrok.tgz
elif [[ $(dpkg --print-architecture) = "arm64" ]]
then
  wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz -O ngrok.tgz
elif [[ $(dpkg --print-architecture) = "amd64" ]]
then
  wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -O ngrok.tgz
fi
tar xvf ngrok.tgz -C /usr/local/bin
rm ngrok.tgz
read -p "Enter your ngrok Authtoken: " auth
ngrok config add-authtoken $auth
ngrok service install --config /root/.config/ngrok/ngrok.yml
tee -a /root/.config/ngrok/ngrok.yml > /dev/null <<EOT
tunnels:
  nginx:
    addr: 443
    proto: http
    schemes:
      - https
    inspect: false
  ssh:
    addr: 22
    proto: tcp
EOT
exit
