#!/bin/bash

sudo apt update
sudo apt install -y nfs-common autofs
if [ ! -f /etc/auto.master.bak ]
then
  sudo cp /etc/auto.master /etc/auto.master.bak
fi
sudo tee -a /etc/auto.master > /dev/null <<EOT
/-  /etc/auto.nfs
EOT
read -p "Enter the IP address of the NFS server: " nfsip
sudo tee /etc/auto.nfs > /dev/null <<EOT
/mnt/Public  -fstype=nfs,rw,sync,soft,intr  ${nfsip}:/srv/NAS/Public
EOT
sudo service autofs reload
rmdir ~/Public
ln -s /mnt/Public ~/Public
exit
