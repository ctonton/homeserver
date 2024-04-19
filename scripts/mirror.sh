#!/bin/bash
if ! dpkg -s rsync nfs-common >/dev/null 2>&1
then
  sudo apt update
  sudo apt install -y rsync nfs-common
fi
sudo umount -q /mnt/part1
sudo umount -q /mnt/part2
clear
lsblk -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT
echo
echo
PS3="Select the partition to copy FROM: "
select part1 in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | sed 's/[^ ]* //') network
do
  if [ $part1 == "network" ]
  then
    read -p "Enter the IP address of the NFS server: " nfs
    sudo mkdir -p /mnt/part1
    sudo mount $nfs:/srv/NAS /mnt/part1
    mount1=/mnt/part1
    break
  fi
  if [ -b /dev/$part1 ]
  then
    if ! grep -q /dev/$part1 /proc/mounts
    then
      sudo mkdir -p /mnt/part1
      sudo mount /dev/$part1 /mnt/part1
    fi
    mount1=$(lsblk -lno MOUNTPOINT /dev/$part1)
    break
  fi
done
echo
echo
PS3="Select the partition to copy TO: "
select part2 in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | sed 's/[^ ]* //') network
do
  if [ $part2 == $part1 ]
  then
    echo "Can not mirror $part1 to $part2"
    sudo umount -q /mnt/part2
    sudo umount -q /mnt/part1
    sudo rmdir /mnt/part2 2>&-
    sudo rmdir /mnt/part1 2>&-
    exit
  fi
  if [ $part2 == "network" ]
  then
    read -p "Enter the IP address of the NFS server: " nfs
    sudo mkdir -p /mnt/part2
    sudo mount $nfs:/srv/NAS /mnt/part2
    mount2=/mnt/part2
  fi
  if [ -b /dev/$part2 ]
  then
    if ! grep -q /dev/$part2 /proc/mounts
    then
      sudo mkdir -p /mnt/part2
      sudo mount /dev/$part2 /mnt/part2
    fi
    mount2=$(lsblk -lno MOUNTPOINT /dev/$part2)
    break
  fi  
done
echo
echo
PS3="Select directory to mirror: "
select dir in Public $(ls $mount1/Public | sed -e 's/^/Public\//')
do
  break
done
echo
echo
echo "**WARNING**"
echo "The data in $mount2/$dir will be irreversibly changed."
read -p "Type \"dry\" to test, \"yes\" to commit, or \"new\" to creat a new copy: " cont
case $cont in
  dry)
    sudo rsync -avhn --del --force --stats $mount1/$dir/ $mount2/$dir
    read -p "Do you want to commit these changes (y/n)? " comt
    if [ $comt == y ]
    then
      sudo rsync -avhW --del --force --info=progress2 $mount1/$dir/ $mount2/$dir
    else
      echo "No changes made."
    fi;;
  yes)
    read -p "Are you sure (y/n)? " comt
    if [ $comt == y ]
    then
      sudo rsync -avhW --del --force --info=progress2 $mount1/$dir/ $mount2/$dir
    else
      echo "No changes made."
    fi;;
  new)
    read -p "Are you sure (y/n)? " comt
    if [ $comt == y ]
    then
      cd $mount1
      sudo tar cf - $dir | (cd $mount2 && tar xvf -)
    else
      echo "No changes made."
    fi;;
  *)
    echo "No changes made.";;
esac
sudo umount -q /mnt/part2
sudo umount -q /mnt/part1
sudo rmdir /mnt/part2 2>&-
sudo rmdir /mnt/part1 2>&-
exit
