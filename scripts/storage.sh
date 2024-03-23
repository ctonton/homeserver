#!/bin/bash

echo
echo "Mounting storage."
umount -q /srv/NAS
mkdir -p /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
echo
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
echo
echo
PS3="Select the partition to use as storage: "
select part in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | cut -d " " -f 2) other
do
if [[ -b /dev/$part ]] && ! grep -q /dev/$part /proc/mounts
then
  sed -i "/$(blkid -o value -s UUID /dev/${part})/d" /etc/fstab
  echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
  mount -a
  mkdir -p /srv/NAS/Public
else
  echo "Device is not available. Manually edit fstab later."
  read -n 1 -s -r -p "Press any key to continue without mounting storage."
fi
break
done
