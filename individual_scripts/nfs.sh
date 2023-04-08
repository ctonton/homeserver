#!/bin/bash
echo "Setting up NFS."
apt-get install -y --no-install-recommends nfs-kernel-server avahi-daemon
tee -a /etc/exports > /dev/null <<EOT
/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check)
EOT
exit
