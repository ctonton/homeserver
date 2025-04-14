#!/bin/bash
opt=0
clear; echo "Manage NGROK users"
until [[ $opt -eq 6 ]]; do
  echo
  echo "1 - Install NGROK"
  echo "2 - Add user"
  echo "3 - List users"
  echo "4 - Remove user"
  echo "5 - Uninstall NGROK"
  echo "6 - Quit"
  echo
  read -p "Enter selection: " opt
  case $opt in
    1)
      case $(dpkg --print-architecture) in
        armhf)
          wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz -O /root/ngrok.tgz;;
        arm64)
          wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz -O /root/ngrok.tgz;;
        amd64)
          wget -q --show-progress https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz -O /root/ngrok.tgz;;
      esac
      tar xvzf ngrok.tgz -C /usr/local/bin
      rm /root/ngrok.tgz
      rm -rf /root/.config/ngrok
      read -p "Enter your ngrok Authtoken: " auth
      ngrok config add-authtoken $auth
      tee -a /root/.config/ngrok/ngrok.yml >/dev/null <<EOT
endpoints:
  - name: ssh
    url: tcp://
    upstream:
      url: 22
  - name: http
    url: https://
    upstream:
      url: 80
EOT
      ngrok service install --config /root/.config/ngrok/ngrok.yml
      systemctl start ngrok
      clear; echo "NGROK installed"
    ;;
    2)
      if ! grep -q 'traffic' /root/.config/ngrok/ngrok.yml; then
        tee -a /root/.config/ngrok/ngrok.yml >/dev/null <<EOT
    traffic_policy:
      on_http_request:
        - actions:
          - type: basic-auth
            config:
              credentials:
EOT
      fi
      read -p "Enter a user name: " user
      read -p "Enter a password: " pass
      echo -e "                - $user:$pass" >>/root/.config/ngrok/ngrok.yml
      systemctl restart ngrok
      clear; echo "$user added"
    ;;
    2)
      clear
      cat /root/.config/ngrok/ngrok.yml | grep '-' | sed '1d' | cut -d '"' -f 2 | cut -d ':' -f 1
    ;;
    3)
      PS3="Enter a number: "
      select use in $(cat /root/.config/ngrok/ngrok.yml | grep '-' | sed '1d' | cut -d '"' -f 2 | cut -d ':' -f 1)
      do
        sed -i "/$use/d" /root/.config/ngrok/ngrok.yml
        break
      done
      systemctl restart ngrok
      clear
      echo "$use removed"
      ;;

    *)
      clear
      echo "Invalid selection"
      ;;
  esac
done
