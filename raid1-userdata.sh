#!/bin/bash
# update OS
yum -y update
# ensure mdadm is installed
yum -y install mdadm
# download jq for json fun
wget -q -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq
chmod 755 /usr/local/bin/jq
# set some variables to work with
AZ=`curl --silent http://169.254.169.254/latest/meta-data/placement/availability-zone/`
IID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
REGION=`curl --silent http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed '$s/.$//'`
# create two volumes of 100GB each - standard io
aws ec2 create-volume --region $REGION --size 100 --availability-zone $AZ | /usr/local/bin/jq .VolumeId > /tmp/volume1
aws ec2 create-volume --region $REGION --size 100 --availability-zone $AZ | /usr/local/bin/jq .VolumeId > /tmp/volume2
# set volume id variables
VID1=`/bin/sed 's/"//g' /tmp/volume1`
VID2=`/bin/sed 's/"//g' /tmp/volume2`
# wait for devices to create
sleep 10
#while [ `aws ec2 describe-volume-status --volume-ids $VID2 --region $REGION | jq -r '.VolumeStatuses[0] | .VolumeStatus.Status'` != "ok" ]; do
#	sleep 3
#done
#
# attach the two volumes we just created
aws ec2 attach-volume --region $REGION --instance-id $IID --volume-id $VID1 --device /dev/xvdb
aws ec2 attach-volume --region $REGION --instance-id $IID --volume-id $VID2 --device /dev/xvdc
# wait for devices to attach
sleep 10
# fdisk sdb
(echo n; echo p; echo 1; echo ; echo ; echo t; echo fd; echo w) | fdisk -c /dev/xvdb
# fdisk sdc
(echo n; echo p; echo 1; echo ; echo ; echo t; echo fd; echo w) | fdisk -c /dev/xvdc
# create raid set and format volume
echo y | mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/xvdb1 /dev/xvdc1
# adjust sync speeds to set up new raid volume quicker
sysctl -w dev.raid.speed_limit_min=25000
sysctl -w dev.raid.speed_limit_max=30000
mkfs.ext4 /dev/md0
# create mount point and mount volume
mkdir /mnt/raid-data
mount /dev/md0 /mnt/raid-data
echo "/dev/md0 /mnt/raid-data ext4 defaults 1 2">> /etc/fstab
logger -s -t RAID-CONFIG Created Volumes $VID1 $VID2
logger -s -t RAID-CONFIG Attached to $IID running in $AZ
rm /tmp/volume1
rm /tmp/volume2
