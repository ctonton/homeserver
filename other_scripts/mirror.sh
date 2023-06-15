#!/bin/bash
sudo umount -q /mnt/part1
sudo umount -q /mnt/part2
sudo mkdir -p /mnt/part1
sudo mkdir -p /mnt/part2
net=$(/sbin/ip route | awk '/src/ { print $1 }' | cut -d "." -f 1-3)
lsblk -l -o TYPE,NAME > list
sed -i '/disk/d' list
sed -i '1d' list
sed -i 's/[^ ]* //' list
echo "network" >> list
clear
lsblk -o NAME,TYPE,SIZE,LABEL
echo
echo
PS3="Select the partition to copy FROM: "
select part1 in $(<list)
do
if [ $part1 == "network" ]
then
  read -p "Enter the IP address of the NFS server: $net." nfs
  sudo mount $net.$nfs:/srv/NAS /mnt/part1
  mount1=/mnt/part1
else
  if [ ! $(findmnt -m /dev/$part1) ]
  then
    sudo mount /dev/$part1 /mnt/part1
  fi
  mount1=$(lsblk -lno MOUNTPOINT /dev/$part1)
fi
break
done
sed -i "/$part1/d" list
clear
lsblk -o NAME,TYPE,SIZE,LABEL
echo
echo
PS3="Select the partition to copy TO: "
select part2 in $(<list)
do
if [ $part2 == "network" ]
then
  read -p "Enter the IP address of the NFS server: $net." nfs
  sudo mount $net.$nfs:/srv/NAS /mnt/part2
  mount2=/mnt/part2
else
  if [ ! $(findmnt -m /dev/$part2) ]
  then
    sudo mount /dev/$part2 /mnt/part2
  fi
  mount2=$(lsblk -lno MOUNTPOINT /dev/$part2)
fi
break
done
clear
echo "**WARNING**"
echo "The data on $part2 will be irreversibly changed."
read -p "Type \"dry\" to test, or \"yes\" to continue: " cont
if [ $cont == "dry" ]
then
  sudo rsync -auPn --delete-before $mount1/Public/ $mount2/Public
fi
if [ $cont == "yes" ]
then
  sudo rsync -auP --delete-before $mount1/Public/ $mount2/Public
else
  echo "No changes made."
fi
sudo umount -q /mnt/part2
sudo umount -q /mnt/part1
sudo rmdir /mnt/part2
sudo rmdir /mnt/part1
rm list
exit
