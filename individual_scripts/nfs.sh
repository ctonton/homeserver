#!/bin/bash
echo "Setting up NFS."
echo "/srv/NAS/Public *(rw,sync,all_squash,no_subtree_check)" >> /etc/exports
exit
