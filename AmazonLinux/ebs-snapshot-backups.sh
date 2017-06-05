#!/bin/bash
#
# This is a backup script intended to backup a single node using snapshots 
#
# This example is for a single node running Apache and MySQL and accepts a short duration of downtime to sync the IO buffer

# setup - make sure jq is present
if [ ! -e /usr/local/bin/jq ]; then
wget -q -O /usr/local/bin/jq http://stedolan.github.io/jq/download/linux64/jq
chmod 755 /usr/local/bin/jq
fi

#
# Test
#

# check timing of backup 'outage' via logger timestamps
logger Start EBS snapshot backup process

# 1. Stop Apache and Mysql
/sbin/service httpd stop
/sbin/service mysqld stop

# 2. Flush buffers
/bin/sync

# 3. Take snapshot
# get volume ID
IID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
VID=`aws ec2 describe-instances --instance-ids $IID | /usr/local/bin/jq -r '.Reservations[0] | .Instances[0] | .BlockDeviceMappings[0] | .Ebs.VolumeId'`
# take snapshot
SNID=`aws ec2 create-snapshot --volume-id $VID --description "your-backup" | /usr/local/bin/jq -r .SnapshotId`
# log snapshot information
logger EBS Snapshot - Created snapshot $SNID for backup on volume $VID

# 4. Start Apache and Mysql
/sbin/service mysqld start
/sbin/service httpd start

# mark snapshot process complete and add timestamp
logger Completed EBS snapshot backup process

# 5. Age/Purge older Snapshots

# get list of snapshots with matching description
SNAPID=`aws ec2 describe-snapshots --filter Name="description",Values="your-backup" | /usr/local/bin/jq -r .Snapshots[].SnapshotId`

# evaluate age of snapshot one at a time and delete if older than 3 days
for ii in $(aws ec2 describe-snapshots --filter Name="description",Values="your-backup" | /usr/local/bin/jq -r .Snapshots[].SnapshotId)
do
  	SNAPSDATE=`aws ec2 describe-snapshots --snapshot-id $ii | /usr/local/bin/jq -r .Snapshots[].StartTime`
        YYY=`date --date $SNAPSDATE '+%s'`
        ZZZ=`date '+%s'`
        DIFF=`expr $ZZZ - $YYY`
        if [ $DIFF -gt 259201 ]
        then
                aws ec2 delete-snapshot --snapshot-id $ii
                logger -s Deleted older snapshot - $ii
        fi
done

