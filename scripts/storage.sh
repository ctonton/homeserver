#!/bin/bash
echo; echo "Mounting storage."
umount -q /srv/NAS
mkdir -p /srv/NAS
chmod 777 /srv/NAS
chown nobody:nogroup /srv/NAS
echo; lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL
echo; echo
PS3="Select the partition to use as storage: "
select part in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | cut -d " " -f 2) other; do break; done
grep -q /dev/$part /proc/mounts || [[ ! -b /dev/$part ]] && (echo "Device is not available. Manually edit fstab or attach media and run this script again."; exit 1)
sed -i "/$(blkid -o value -s UUID /dev/${part})/d" /etc/fstab
echo "UUID=$(blkid -o value -s UUID /dev/${part})  /srv/NAS  $(blkid -o value -s TYPE /dev/${part})  defaults,nofail  0  0" >> /etc/fstab
mount -a
mkdir -p /srv/NAS/Public
rm $0
exit 0
