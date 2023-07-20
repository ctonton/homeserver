#!/bin/bash
if ! dpkg -s rsync nfs-common >/dev/null 2>&1
then
  sudo apt update
  sudo apt install -y rsync nfs-common
fi
sudo umount -q /mnt/part1
sudo umount -q /mnt/part2
clear
lsblk -o NAME,TYPE,SIZE,LABEL
echo
echo
lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | sed 's/[^ ]* //' > list
echo "network" >> list
PS3="Select the partition to copy FROM: "
select part1 in $(<list)
do
  if [ $part1 == "network" ]
  then
    read -p "Enter the IP address of the NFS server: " nfs
    sudo mkdir -p /mnt/part1
    sudo mount $nfs:/srv/NAS /mnt/part1
    mount1=/mnt/part1
    break
  fi
  if [ ! -z /dev/$part1 ]
  then
    if [ $(findmnt -m /dev/$part1 >/dev/null) ]
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
sed -i "/$part1/d" list
PS3="Select the partition to copy TO: "
select part2 in $(<list)
do
  if [ $part2 == "network" ]
  then
    read -p "Enter the IP address of the NFS server: " nfs
    sudo mkdir -p /mnt/part2
    sudo mount $nfs:/srv/NAS /mnt/part2
    mount2=/mnt/part2
    break
  fi
  if [ ! -z /dev/$part2 ]
  then
    if [ $(findmnt -m /dev/$part2 >/dev/null) ]
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
ls $mount1/Public > list
sed -i -e 's/^/Public\//' list
PS3="Select directory to mirror: "
select dir in Public $(<list)
do
  if [ ! -z $dir ]
  then
    break
  fi
done
echo
echo
echo "**WARNING**"
echo "The data in $mount2/$dir will be irreversibly changed."
read -p "Type \"dry\" to test, or \"yes\" to continue: " cont
case $cont in
  dry)
    sudo rsync -auPn $mount1/$dir/ $mount2/$dir
    read -p "Do you want to commit these changes (y/n)? " comt
    if [ $comt == y ]
    then
      sudo rsync -auP --delete-before $mount1/$dir/ $mount2/$dir
    else
      echo "No changes made"
    fi
    ;;
  yes)
    read -p "Are you sure (y/n)? " comt
    if [ $comt == y ]
    then
      sudo rsync -auP --delete-before $mount1/$dir/ $mount2/$dir
    else
      echo "No changes made"
    fi
    ;;
  *)
    echo "No changes made"
    ;;
esac
sudo umount -q /mnt/part2
sudo umount -q /mnt/part1
sudo rmdir /mnt/part2
sudo rmdir /mnt/part1
rm list
exit
