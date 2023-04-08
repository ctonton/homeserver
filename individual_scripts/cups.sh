#!/bin/bash
echo "Setting up CUPS."
apt-get install -y --no-install-recommends cups printer-driver-hpcups
usermod -aG lpadmin root
cupsctl --remote-admin --user-cancel-any
read -p "Enter the static IP address of the default printer: $(/sbin/ip route | awk '/src/ { print $1 }' | cut -f1-3 -d".")." prip
defip=$(/sbin/ip route | awk '/src/ { print $1 }' | cut -f1-3 -d".").${prip}
read -p "Enter a name for the default printer: " defpr
lpadmin -p $defpr -E -v ipp://${defip}/ipp/print -m everywhere
lpadmin -d $defpr
systemctl restart cups
exit
