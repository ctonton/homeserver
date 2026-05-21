#!/bin/bash
r="mbuffer screen xfsprogs"
dpkg -l $r &>/dev/null || (sudo apt update && sudo apt install -y $r)
echo
lsblk -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT
echo
PS3="Select source partition: "
select dev1 in $(lsblk -l -o TYPE,NAME | awk '/part/ {print $2}'); do break; done
echo
PS3="Select destination disk: "
select dev2 in $(lsblk -l -o TYPE,NAME | grep -v "$dev1" | awk '/disk/ {print $2}'); do break; done
echo "**CAUTION** **IMPORTANT**"
echo "All data contained on disk $dev2 will be lost."
echo "Are you certain that you want to copy to $dev2?"
read -p "Type \"$dev2\" here to confirm: " c
[[ $c != $dev2 ]] && echo "The job has been canceled. No data was written or erased." && exit 1
if grep -q /dev/$dev1 /proc/mounts; then
  src="$(lsblk -lno MOUNTPOINT /dev/$dev1 | head -n 1)"
else
  sudo mkdir -p -v /mnt/src
  sudo umount -f -l /mnt/src
  sudo mount -v /dev/$dev1 /mnt/src
  src="/mnt/src"
fi
sudo umount -A -f -l /dev/$dev2
sudo wipefs -a -v /dev/$dev2
sudo parted /dev/$dev2 mklabel gpt
sudo mkfs.xfs -f /dev/$dev2
sudo umount -f -l /mnt/dst
sudo mkdir -p -v /mnt/dst
sudo mount -v /dev/$dev2 /mnt/dst
echo "Starting the copy job inside of a screen session."
sudo screen -d -m bash -c "tar -b 2048 --directory=\"$src\" --exclude='Downloads' -cf - Public | mbuffer -s 1M -m 256M | tar -b 2048 --directory=/mnt/dst -xf -; umount -q /mnt/src; umount -q /mnt/dst; rmdir /mnt/src /mnt/dst"
exit 0
