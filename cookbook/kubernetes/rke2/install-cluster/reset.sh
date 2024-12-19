#!/bin/bash

############################
###### Reset ###############

helm uninstall cilium
helm uninstall kube-vip-cloud-provider
helm uninstall kube-vip
rm -rf ./kube
rke2-killall.sh
rke2-uninstall.sh
reboot
