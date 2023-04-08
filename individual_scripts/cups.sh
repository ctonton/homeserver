#!/bin/bash
echo "Setting up CUPS."
usermod -aG lpadmin root
cupsctl --remote-admin --user-cancel-any
read -p "Do you want to set up the default printer now? (y/n): " cont
if [ $cont == "y" ]
then
  read -p "Enter the static IP address of the default printer: $(/sbin/ip route | awk '/src/ { print $1 }' | cut -f1-3 -d".")." prip
  defip=$(/sbin/ip route | awk '/src/ { print $1 }' | cut -f1-3 -d".").${prip}
  read -p "Enter a name for the default printer: " defpr
  lpadmin -p $defpr -E -v ipp://${defip}/ipp/print -m everywhere
  lpadmin -d $defpr
fi
exit
