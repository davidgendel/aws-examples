#!/bin/bash
####################################################################################################
#    Highly Available NAT instance solution using Autoscaling and Peer-Monitoring
#    Adapted and updated from http://aws.amazon.com/articles/2781451301784570
#
#    You will need to run this script on two different EC2 instances which are each wrapped in 
#    their own autoscaling group and using this as user-data. This solution also requires a role
#    with the following policy for the EC2 instances:
#
# {
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Action": [
#                "ec2:DescribeInstances",
#                "ec2:CreateRoute",
#                "ec2:ReplaceRoute",
#                "ec2:StartInstances",
#                "ec2:StopInstances",
#                "ec2:ModifyInstanceAttribute",
#                "ec2:DescribeInstanceStatus",
#                "autoscaling:DescribeAutoScalingGroups",
#                "ec2:AssociateAddress"
#            ],
#            "Effect": "Allow",
#            "Resource": "*"
#        }
#    ]
# }
#
####################################################################################################
# HA NAT SERVER A/B 
####################################################################################################

# This script will monitor another NAT instance and take over its routes if communication with the other instance fails
# My route to grab when I come back up - Route table that I NAT for in healthy/original state
My_RT_ID="rtb-00000"
# Route table that the partner NAT instance will manage/operate in healthy/original state
NAT_RT_ID="rtb-00000"
# AutoScaling Group for partner NAT server
PNAT_ASG_NAME="auto-scaling-group-name"
# My Elastic IP Address allocation id
EIPALLOCID="eipalloc-99999999"

# Health Check variables
Num_Pings=10
Ping_Timeout=1
Wait_Between_Test=15

####################################################################
####################################################################
IID=$(curl --silent http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl --silent http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed '$s/.$//')
AWSCLI="aws --output text --region $REGION"
# Log to stdout and stderr as well as syslog
exec 1> >(logger -s -t $(basename $0)) 2>&1
# Attach EIP
aws ec2 associate-address --region $REGION --instance-id $IID --allocation-id $EIPALLOCID
#Setup NAT
yum -y update
aws ec2 modify-instance-attribute --instance-id $IID --source-dest-check "{\"Value\": false}" --region $REGION
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv4/conf/eth0/send_redirects
/sbin/iptables -t nat -A POSTROUTING -o eth0 -s 0.0.0.0/0 -j MASQUERADE
/sbin/iptables-save > /etc/sysconfig/iptables
mkdir -p /etc/sysctl.d/
cat <<EOF > /etc/sysctl.d/nat.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.eth0.send_redirects = 0
EOF

# Tune the OS for high network traffic - adjust as necessary
yum -y install conntrack-tools
modprobe nf_conntrack_ipv4
cat <<OTHERLIMIT >>/etc/sysctl.conf
#
#
# Point Inside NAT Tuning
#
net.ipv4.netfilter.ip_conntrack_max = 131072
net.ipv4.ip_local_port_range = 32768    63000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_forward = 1
net.ipv4.conf.eth0.send_redirects = 0
#
#
OTHERLIMIT
sysctl -p
#
# Wait until I am healthy and passing system checks before assuming a route
MY_EC2_HEALTH=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].InstanceState[].Name[]')
MY_EC2_SYS_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].SystemStatus[].Status[]')
MY_EC2_INST_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].InstanceStatus[].Status[]')
while [ "$MY_EC2_HEALTH" != "running" -o "$MY_EC2_SYS_STAT" != "ok" -o "$MY_EC2_INST_STAT" != "ok" ]; do
  sleep 15
  MY_EC2_HEALTH=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].InstanceState[].Name[]')
  MY_EC2_SYS_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].SystemStatus[].Status[]')
  MY_EC2_INST_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].InstanceStatus[].Status[]')
done
#
echo "-- Starting NAT monitor"
echo "-- Adding this instance to $My_RT_ID default route on start"
$AWSCLI ec2 replace-route --route-table-id $My_RT_ID --destination-cidr-block 0.0.0.0/0 --instance-id $IID
# If replace-route failed, then the route might not exist and may need to be created instead
if [ "$?" != "0" ]; then
  $AWSCLI ec2 create-route --route-table-id $My_RT_ID --destination-cidr-block 0.0.0.0/0 --instance-id $IID
fi
#
while [ . ]; do
  # Check my health and if healthy make sure I am running my route
  if [ $($AWSCLI ec2 describe-route-tables --route-table $My_RT_ID --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0`].[InstanceId]') != "$IID" ]; then
    MY_EC2_HEALTH=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].InstanceState[].Name[]')
    MY_EC2_SYS_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].SystemStatus[].Status[]')
    MY_EC2_INST_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $IID --query 'InstanceStatuses[*].InstanceStatus[].Status[]')
    if [ "$MY_EC2_HEALTH" == "running" -a "$MY_EC2_SYS_STAT" == "ok" -a "$MY_EC2_INST_STAT" == "ok" ]; then
        echo "-- I am not currently managing $My_RT_ID however I am healthy and will now take over my primary route - $My_RT_ID"
        $AWSCLI ec2 replace-route --route-table-id $My_RT_ID --destination-cidr-block 0.0.0.0/0 --instance-id $IID
    fi
  fi
  # Get the other NAT instance's IP
  NAT_ID=$($AWSCLI autoscaling describe-auto-scaling-groups --auto-scaling-group-names $PNAT_ASG_NAME --query 'AutoScalingGroups[*].Instances[?LifecycleState==`InService`].[InstanceId]')
  NAT_IP=$($AWSCLI ec2 describe-instances --instance-id $NAT_ID --query 'Reservations[*].Instances[*].PrivateIpAddress[]')
  # Check health of other NAT instance via ping
  pingresult=$(ping -c $Num_Pings -W $Ping_Timeout $NAT_IP | grep time= | wc -l)
  # Also check EC2 instance status to determine health
  EC2_HEALTH=$($AWSCLI ec2 describe-instance-status --instance-ids $NAT_ID --query 'InstanceStatuses[*].InstanceState[].Name[]')
  EC2_SYS_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $NAT_ID --query 'InstanceStatuses[*].SystemStatus[].Status[]')
  EC2_INST_STAT=$($AWSCLI ec2 describe-instance-status --instance-ids $NAT_ID --query 'InstanceStatuses[*].InstanceStatus[].Status[]')
  # Check to see if the health checks succeeded, if not take over route
  if [ "$pingresult" == "0" ]; then
      echo "-- Other NAT ping heartbeat failed, taking over $NAT_RT_ID default route"
      $AWSCLI ec2 replace-route --route-table-id $NAT_RT_ID --destination-cidr-block 0.0.0.0/0 --instance-id $IID
      sleep 30
  elif [ "$EC2_HEALTH" != "running" -o "$EC2_SYS_STAT" != "ok" -o "$EC2_INST_STAT" != "ok" ]; then
      echo "-- Other NAT status heartbeat failed, taking over $NAT_RT_ID default route"
      $AWSCLI ec2 replace-route --route-table-id $NAT_RT_ID --destination-cidr-block 0.0.0.0/0 --instance-id $IID
      sleep 30
  else
    sleep $Wait_Between_Test
  fi

done
