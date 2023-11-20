#!/bin/bash
if [[ ! -f /root/.config/ngrok/ngrok.yml ]]
then
  echo "NGROK not installed."
  exit
fi
opt=0
clear
echo "Manage NGROK users"
until [ $opt -eq 4 ]
do
  echo
  echo "1 - Add user"
  echo "2 - Remove user"
  echo "3 - List users"
  echo "4 - Quit"
  echo
  read -p "Enter selection: " opt
  case $opt in
    1)
      if ! grep -q 'basic' /root/.config/ngrok/ngrok.yml
      then
        base=$(echo -e "    basic_auth:")
        sed -i "/inspect/a\\$base" /root/.config/ngrok/ngrok.yml
      fi
      read -p "Enter a user name: " use
      read -p "Enter a password: " pass
      line=$(echo -e "      - \"$use:$pass\"")
      sed -i "/basic/a\\$line" /root/.config/ngrok/ngrok.yml
      clear
      echo "$use added"
      ;;
    2)
      PS3="Enter a number: "
      select use in $(cat /root/.config/ngrok/ngrok.yml | grep '-' | sed '1d' | cut -d '"' -f 2 | cut -d ':' -f 1)
      do
        sed -i "/$use/d" /root/.config/ngrok/ngrok.yml
        break
      done
      clear
      echo "$use removed"
      ;;
    3)
      clear
      cat /root/.config/ngrok/ngrok.yml | grep '-' | sed '1d' | cut -d '"' -f 2 | cut -d ':' -f 1
      ;;
    *)
      clear
      echo "Invalid selection"
      ;;
  esac
done
exit
