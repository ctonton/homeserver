#tee /root/.config/qBittorrent/lanchk.sh > /dev/null <<'EOT'
#!/bin/bash
##if /sbin/ip route | grep "default"
#then
#  OLD=$(cat /root/.config/route | cut -d '/' -f 1)
#  NEW=$(/sbin/ip route | awk '/src/ { print $1 }' | cut -d '/' -f 1)
#  if [[ $OLD != $NEW ]]
#  then
#    sed -i "s/$OLD/$NEW/g" /root/.config/qBittorrent/qBittorrent.conf
#    ufw delete allow from $(cat /root/.config/route)
#    ufw allow from $(/sbin/ip route | awk '/src/ { print $1 }')
#    echo $(/sbin/ip route | awk '/src/ { print $1 }') > /root/.config/route
#  fi
#fi
#exit
#EOT
#chmod +x /root/.config/qBittorrent/lanchk.sh