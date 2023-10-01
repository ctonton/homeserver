#!/bin/bash
if ! dpkg -s autofs nfs-common >/dev/null 2>&1
then
  sudo apt update
  sudo apt install -y autofs nfs-common
fi
if [ ! -f /etc/auto.master.bak ]
then
  sudo cp /etc/auto.master /etc/auto.master.bak
fi
sudo tee /etc/auto.master > /dev/null <<EOT
+auto.master
/-  /etc/auto.nfs  browse
EOT
read -p "Enter the address of the NFS server: " nfsip
sudo tee /etc/auto.nfs > /dev/null <<EOT
/mnt/Public  -fstype=nfs,rw,sync,soft,intr,retrans=1,retry=0  ${nfsip}:/srv/NAS/Public
EOT
sudo service autofs reload
rm -df ~/Public
ln -s /mnt/Public ~/Public
exit
