#!/bin/sh
#
# This is a simple bootstrapping script designed for automatically configuring an Amazon Linux instance to serve as a NAT instance.
# This is great to use in combination with Auto Scaling - min1/max1 for a self healing NAT solution
#
yum -y update
IID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
REGION=`curl --silent http://169.254.169.254/latest/meta-data/placement/availability-zone/ | sed '$s/.$//'`
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
#
# DON'T FORGET TO UPDATE THIS LINE WITH YOUR ROUTE TABLE - if you need more than one, copy and paste multiple lines with
# multiple route tables
#
aws ec2 replace-route --route-table-id rtb-999999 --destination-cidr-block 0.0.0.0/0 --instance-id $IID

