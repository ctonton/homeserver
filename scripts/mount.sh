#!/bin/bash
echo <password> | sudo -S mount -t nfs4 -o soft,timeo=30,retrans=2,_netdev <address>:/srv/NAS/Public ~/Public
nemo -q
nemo ~/Public
exit
