#!/bin/bash
mbuffer --version &>/dev/null || (apt update; apt install mbuffer)
echo
echo "Copy to a DEV (device), over LAN (unsecure), or over WAN (secure)?"
PS3="Select option: "
select mode in DEV LAN WAN; do break; done
case $mode in
  DEV)
    echo
    lsblk -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT
    echo
    PS3="Select the partition to use: "
    select part2 in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | sed 's/[^ ]* //'); do break; done
    grep -q /dev/"$part2" /proc/mounts || (umount /mnt/part2 &>/dev/null; mkdir -p /mnt/part2; mount /dev/"$part2" /mnt/part2)
    until [[ $d == "FROM" || $d == "TO" ]]; do
      echo
      echo "**CAUTION** **IMPORTANT**"
      echo "Do you want to copy FROM or TO /dev/$part2?"
      read -p "Type FROM or TO here: " d
    done
    [[ $d == "FROM" ]] && (srce="$(lsblk -lno MOUNTPOINT /dev/"$part2")"; dest="/srv/NAS")
    [[ $d == "TO" ]] && (srce="/srv/NAS"; dest="$(lsblk -lno MOUNTPOINT /dev/"$part2")")
    tar -b8 --directory="$srce" --exclude='Downloads' -cf - Public | mbuffer -s 4K -m 256M | tar -b8 --directory="$dest" -xf -
    mkdir -p "$dest/Public/Downloads"; chmod -R 777 "$dest/Public"; chown -R nobody:nogroup "$dest/Public"
    [ -d /mnt/part2 ] && (umount /mnt/part2; rmdir /mnt/part2)
  ;;
  LAN)
    read -p "Enter a valid ip address for the remote server: " remote
    ping -c 1 "$remote" &>/dev/null || (echo "Remote server unavailable."; exit 64)
    ssh -T root@"$remote" &>/dev/null <<HERE
mbuffer --version &>/dev/null || (apt update; apt install mbuffer)
mbuffer -s 4K -m 128M -I 7777 | tar --directory=/srv/NAS -b8 -xf - &
HERE
    tar --directory=/srv/NAS --exclude='Downloads' -b8 -cf - Public | mbuffer -s 4k -m 128M -O "$remote":7777
    ssh root@"$remote" "mkdir -p /srv/NAS/Public/Downloads; chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
  ;;
  WAN)
    read -p "Enter a valid ip address for the remote server: " remote
    ping -c 1 "$remote" &>/dev/null || (echo "Remote server unavailable."; exit 64)
    tar -b8 --directory=/srv/NAS --exclude='Downloads' -cf - Public | mbuffer -s 4K -m 64M | ssh root@"$remote" "tar -b8 --directory=/srv/NAS -xf -"
    ssh root@"$remote" "mkdir -p /srv/NAS/Public/Downloads; chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
  ;;
esac
exit 0
