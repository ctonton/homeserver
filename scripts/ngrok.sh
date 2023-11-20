#!/bin/bash
echo "Installing ngrok."
case $(dpkg --print-architecture) in
  armhf)
    wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz -O /root/ngrok.tgz;;
  arm64)
    wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz -O /root/ngrok.tgz;;
  amd64)
    wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -O /root/ngrok.tgz;;
esac
tar xvf ngrok.tgz -C /usr/local/bin
rm /root/ngrok.tgz
rm -rf /root/.config/ngrok
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
systemctl start ngrok
sed -i 's/\#auth/auth/g' /etc/nginx/sites-available/default
nginx -s reload
wget https://github.com/ctonton/homeserver/raw/main/scripts/ngrok_users.sh -O /root/ngrok_users.sh
chmod +x /root/ngrok_users.sh
rm $0
bash /root/ngrok_users.sh
exit
