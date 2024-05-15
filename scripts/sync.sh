#!/bin/bash
function rsetup {
  ssh root@"$remote" "if ! rsync --version >/dev/null 2>&1; then apt update && apt install -y rsync; fi"
  ssh root@"$remote" 'tee /etc/rsyncd.conf >/dev/null <<EOT
[Public]
  path = /srv/NAS/Public
  comment = Public Directory
  read only = false
EOT'
}
if ! rsync --version >/dev/null 2>&1; then
  apt update && apt install -y rsync
  tee /etc/rsyncd.conf >/dev/null <<EOT
[Public]
  path = /srv/NAS/Public
  comment = Public Directory
  read only = false
EOT
fi
if [[ -n $1 ]]; then
  remote="$1"
  if ! ping -c 1 "$remote" >/dev/null 2>&1; then
    exit 64
  fi
  if ! ssh root@"$remote" 'rsync --version >/dev/null 2>&1'; then
    rsetup
  fi
  rsync -ahW --inplace --del --force --exclude 'Downloads' /srv/NAS/Public/ root@"$remote":/srv/NAS/Public
  old=$(grep -ao -m 1 '//.*/srv' /srv/NAS/Public/Downloads/working/sources.xml | cut -d "/" -f 3)
  sed "s/$old/$remote/g" /srv/NAS/Public/Downloads/working/sources.xml | ssh root@"$remote" 'cat - > /srv/NAS/Public/Downloads/working/sources.xml'
  old=$(grep -ao -m 1 '//.*/srv' /srv/NAS/Public/Downloads/working/MyVideos131.db | cut -d "/" -f 3)
  sed "s/$old/$remote/g" /srv/NAS/Public/Downloads/working/MyVideos131.db | ssh root@"$remote" 'cat - > /srv/NAS/Public/Downloads/working/MyVideos131.db'
  ssh root@"$remote" "chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
  exit 0
fi
echo
echo "Sync to a DEV (device), over LAN (unsecure), or over WAN (secure)?"
PS3="Select option: "
select mode in DEV LAN WAN; do
  case $mode in
    DEV)
      echo
      lsblk -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT
      echo
      PS3="Select the partition to sync: "
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
      echo "Do you want to sync FROM or TO /dev/$part2?"
      until [[ $dire == "FROM" || $dire == "TO" ]]; do
        read -pr "Type FROM or TO here: " dire
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
      break;;
    LAN)
      read -pr "Enter a valid ip address for the remote server: " remote
      if ! ping -c 1 "$remote" >/dev/null 2>&1; then
        echo "Remote server unavailable."
        exit 64
      fi
      if ! ssh root@"$remote" 'rsync --daemon >/dev/null 2>&1'; then
        rsetup
        ssh root@"$remote" 'rsync --daemon'
      fi
      srce="/srv/NAS/Public"
      dest="$remote::Public"
      break;;
    WAN)
      read -pr "Enter a valid ip address for the remote server: " remote
      if ! ping -c 1 "$remote" >/dev/null 2>&1; then
        echo "Remote server unavailable."
        exit 64
      fi
      if ! ssh root@"$remote" 'rsync --version >/dev/null 2>&1'; then
        rsetup
      fi
      srce="/srv/NAS/Public"
      dest="root@$remote:/srv/NAS/Public"
      break;;
  esac
done
rsync -avhn --del --stats --exclude 'Downloads' "$srce"/ "$dest"
read -pr "Do you want to commit these changes (y/n)? " comt
if [ "$comt" == "y" ]; then
  rsync -avhW --inplace --del --force --progress --exclude 'Downloads' "$srce"/ "$dest"
else
  echo "No changes made."
fi
case $mode in
  DEV)
    if [ "$comt" == "y" ]; then
      remote=$(ip route | awk '/default/ {print $9}')
      old=$(grep -ao -m 1 '//.*/srv' "$srce"/Downloads/working/sources.xml | cut -d "/" -f 3)
      sed "s/$old/$remote/g" "$srce"/Downloads/working/sources.xml > "$dest"/Downloads/working/sources.xml
      old=$(grep -ao -m 1 '//.*/srv' "$srce"/Downloads/working/MyVideos131.db | cut -d "/" -f 3)
      sed "s/$old/$remote/g" "$srce"/Downloads/working/MyVideos131.db > "$dest"/Downloads/working/MyVideos131.db
      chmod -R 777 "$dest"; chown -R nobody:nogroup "$dest"
    fi
    umount /mnt/"$part2" >/dev/null 2>&1
    rmdir /mnt/part2 >/dev/null 2>&1;;
  LAN)
    if [ "$comt" == "y" ]; then
      old=$(grep -ao -m 1 '//.*/srv' "$srce"/Downloads/working/sources.xml | cut -d "/" -f 3)
      sed "s/$old/$remote/g" "$srce"/Downloads/working/sources.xml | ssh root@"$remote" 'cat - > /srv/NAS/Public/Downloads/working/sources.xml'
      old=$(grep -ao -m 1 '//.*/srv' "$srce"/Downloads/working/MyVideos131.db | cut -d "/" -f 3)
      sed "s/$old/$remote/g" "$srce"/Downloads/working/MyVideos131.db | ssh root@"$remote" 'cat - > /srv/NAS/Public/Downloads/working/MyVideos131.db'
      ssh root@"$remote" "chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
    fi
    ssh root@"$remote" 'killall rsync';;
  WAN)
    if [ "$comt" == "y" ]; then
      old=$(grep -ao -m 1 '//.*/srv' "$srce"/Downloads/working/sources.xml | cut -d "/" -f 3)
      sed "s/$old/$remote/g" "$srce"/Downloads/working/sources.xml | ssh root@"$remote" 'cat - > /srv/NAS/Public/Downloads/working/sources.xml'
      old=$(grep -ao -m 1 '//.*/srv' "$srce"/Downloads/working/MyVideos131.db | cut -d "/" -f 3)
      sed "s/$old/$remote/g" "$srce"/Downloads/working/MyVideos131.db | ssh root@"$remote" 'cat - > /srv/NAS/Public/Downloads/working/MyVideos131.db'
      ssh root@"$remote" "chmod -R 777 /srv/NAS/Public; chown -R nobody:nogroup /srv/NAS/Public"
    fi;;
esac
exit 0
