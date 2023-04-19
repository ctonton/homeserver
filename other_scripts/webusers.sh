#!/bin/bash
clear
loo=0
until [ $loo -eq 4 ]
do
  echo
  echo "1 - List users"
  echo "2 - Add user"
  echo "3 - Remove user"
  echo "4 - quit"
  echo
  read -p "Enter selection: :" loo
  if [ $loo -eq 1 ]
  then
    echo
    cat /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -eq 2 ]
  then
    read -p "Enter a user name: " use
    echo -n "${use}:" >> /etc/nginx/.htpasswd
    openssl passwd -apr1 >> /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -eq 3 ]
  then
    read -p "Enter a user name to remove: " use
    sed -i "/$use/d" /etc/nginx/.htpasswd
    loo=0
  fi
  if [ $loo -ne 0 ]
  then
    echo "Invalid selection."
    echo
  fi
done
exit
