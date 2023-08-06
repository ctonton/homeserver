#!/bin/bash
clear
echo "Setup ngrok."
read -p "Enter your ngrok Authtoken: " auth
ngrok config add-authtoken $auth
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
ngrok service install --config /root/.config/ngrok/ngrok.yml
exit
