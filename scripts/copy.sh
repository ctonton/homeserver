#!/bin/bash
if ! mbuffer --version >/dev/null 2>&1; then
  apt update && apt install -y mbuffer
fi
echo
echo "Copy to a DEV (device), over LAN (unsecure), or over WAN (secure)?"
PS3="Select option: "
select mode in DEV LAN WAN; do
  case $mode in
    DEV)
      echo
      lsblk -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT
      echo
      PS3="Select the partition to use: "
      select part2 in $(lsblk -l -o TYPE,NAME | sed '1d' | sed '/disk/d' | sed 's/[^ ]* //'); do
        if ! grep -q /dev/"$part2" /proc/mounts; then
          umount /mnt/part2 >/dev/null 2>&1
          mkdir -p /mnt/part2
          mount /dev/"$part2" /mnt/part2
        fi
        break
      done
      echo
      echo "**CAUTION** **IMPORTANT**"
      echo "Do you want to copy FROM or TO /dev/$part2?"
      until [[ $dire == "FROM" || $dire == "TO" ]]; do
        read -p "Type FROM or TO here: " dire
        case $dire in
          FROM)
            srce="$(lsblk -lno MOUNTPOINT /dev/"$part2")/Public"
            dest="/srv/NAS/Public";;
          TO)
            srce="/srv/NAS/Public"
            dest="$(lsblk -lno MOUNTPOINT /dev/"$part2")/Public";;
          *)
            echo "Incorect input.";;
        esac
      done
      tar -b8 --directory="$srce" --exclude=Downloads -cf - . | mbuffer -s 4K -m 128M | tar -b8 --directory="$dest" -xf -
      break;;
    LAN)
      read -p "Enter a valid ip address for the remote server: " remote
      if ! ping -c 1 "$remote" >/dev/null 2>&1; then
        echo "Remote server unavailable."
        exit 64
      fi
      ssh root@"$remote" "if ! mbuffer --version >/dev/null 2>&1; then apt update && apt install mbuffer; fi"
      ssh root@"$remote" "mkdir -p /srv/NAS/Public/Downloads"
      ssh root@"$remote" "mbuffer -s 4K -m 128M -I 777 | tar --directory=/srv/NAS/Public -b8 -xf - &"
      tar --directory=/srv/NAS/Public --exclude=Downloads -b8 -cf - . | mbuffer -s 4k -m 128M -O "$remote":777
      ssh root@"$remote" "chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
      break;;
    WAN)
      read -p "Enter a valid ip address for the remote server: " remote
      if ! ping -c 1 "$remote" >/dev/null 2>&1; then
        echo "Remote server unavailable."
        exit 64
      fi
      tar -b8 --directory=/srv/NAS/Public --exclude=Downloads -cf - . | mbuffer -s 4K -m 32M | ssh root@"$remote" "tar -b8 --directory=/srv/NAS/Public -xf -"
      ssh root@"$remote" "chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
      break;;
  esac
done
exit 0
