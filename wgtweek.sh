#!/bin/bash
sed -i '/forward=1/s/^# *//' /etc/sysctl.conf
sed -i '/forwarding=1/s/^# *//' /etc/sysctl.conf
ufw allow from 10.7.0.0/24
ufw allow 51820/udp
exit
