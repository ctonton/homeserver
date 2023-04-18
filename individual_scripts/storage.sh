#!/bin/bash
echo "Mounting storage."
mkdir /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
blkid
echo
read -p "Disk partition to mount (ex. sda2): " part
if [ -b /dev/$part ] && ! grep -q /dev/$part /proc/mounts
then
  uniq=$(blkid -o value -s UUID /dev/${part})
  type=$(blkid -o value -s TYPE /dev/${part})
  echo "UUID=${uniq}  /srv/NAS  ${type}  defaults,x-systemd.before=nfs-kernel-server.service,nofail  0  0" >> /etc/fstab
  mount -a
else
  echo "#UUID=  /srv/NAS    defaults,x-systemd.before=nfs-kernel-server.service,nofail  0  0" >> /etc/fstab
  read -n 1 -s -r -p "Device is not available. Press any key to exit without mounting storage."
fi
exit
