#!/bin/bash
opt=0
clear
echo "Manage HTTP users"
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
      read -p "Enter a user name: " use
      if [[ -f /etc/nginx/.htpasswd ]]; then
        echo -n "${use}:" >> /etc/nginx/.htpasswd
      else
        echo -n "${use}:" > /etc/nginx/.htpasswd
      fi
      openssl passwd -apr1 >> /etc/nginx/.htpasswd
      clear
      echo "$use added"
      ;;
    2)
      if [[ -f /etc/nginx/.htpasswd ]]; then
        PS3="Enter a number: "
        select use in $(cat /etc/nginx/.htpasswd | cut -d ':' -f 1); do
          sed -i "/$use/d" /etc/nginx/.htpasswd
          break
        done
        if [ -z "$(cat ${file_name})" ]; then
          rm /etc/nginx/.htpasswd
        fi
        clear
        echo "$use removed"
      else
        clear
        echo "No users exist."
      fi
      ;;
    3)
      clear
      cat /etc/nginx/.htpasswd | cut -d ':' -f 1
      ;;
    *)
      clear
      echo "Invalid selection"
      ;;
  esac
done
exit
