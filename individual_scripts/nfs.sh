#!/bin/bash
echo "Setting up NFS."
tee -a /etc/exports > /dev/null <<EOT
/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check)
EOT
exit
