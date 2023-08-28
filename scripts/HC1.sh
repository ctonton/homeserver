#!/bin/bash

tee /boot/armbianEnv.txt > /dev/null <<EOT
board_name=hc1
usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u
EOT
rm $0
systemctl reboot
exit
