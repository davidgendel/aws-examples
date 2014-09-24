#!/bin/bash
# written for amazon linux base 64 bit - september 2014 or newer
# update OS
yum -y update
# install stress tool
yum -y install stress
logger -s -t AWS-STRESS-DEMO Begin stress test demo
# begin stressing system in series of ramping up waves, logging stages to messages log
dd if=/dev/zero of=speedtest bs=128k count=9000 conv=fdatasync &
stress --cpu 2 --io 2 --vm 1 --hdd 1 -t 200 
wget -O /tmp/test.iso http://download.fedoraproject.org/pub/fedora/linux/releases/20/Live/x86_64/Fedora-Live-Desktop-x86_64-20-1.iso &
logger -s -t AWS-STRESS-DEMO Stage One Complete - stress test demo
stress --cpu 4 --io 4 --vm 2 --hdd 4 -t 600
dd if=/dev/zero of=speedtest1 bs=64k count=9000 conv=fdatasync &
stress --cpu 8 --io 8 --vm 3 --hdd 4 -t 900
stress --cpu 1 --io 2 --vm 1 --hdd 1 -t 400
dd if=/dev/zero of=speedtest2 bs=128k count=9000 conv=fdatasync &
wget -O /tmp/test2.iso http://releases.ubuntu.com/saucy/ubuntu-13.10-server-i386.iso &
logger -s -t AWS-STRESS-DEMO Stage Two Complete - stress test demo
stress --cpu 4 --io 4 --vm 2 --hdd 4 -t 600
dd if=/dev/zero of=speedtest3 bs=128k count=9000 conv=fdatasync &
stress --cpu 8 --io 8 --vm 3 --hdd 4 -t 900
stress --cpu 1 --io 2 --vm 1 --hdd 1 -t 400
dd if=/dev/zero of=speedtest4 bs=128k count=9000 conv=fdatasync &
wget -O /tmp/test3.iso http://download.fedoraproject.org/pub/fedora/linux/releases/20/Live/x86_64/Fedora-Live-Desktop-x86_64-20-1.iso &
logger -s -t AWS-STRESS-DEMO Stage Three Complete - stress test demo
stress --cpu 4 --io 4 --vm 2 --hdd 4 -t 600
dd if=/dev/zero of=speedtest5 bs=64k count=9000 conv=fdatasync &
stress --cpu 8 --io 8 --vm 3 --hdd 4 -t 900
stress --cpu 1 --io 2 --vm 1 --hdd 1 -t 400
dd if=/dev/zero of=speedtest bs=128k count=9000 conv=fdatasync &
wget -O /tmp/test4.iso http://releases.ubuntu.com/saucy/ubuntu-13.10-server-i386.iso &
logger -s -t AWS-STRESS-DEMO Process Complete - stress test demo
