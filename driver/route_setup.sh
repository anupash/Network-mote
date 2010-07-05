#!/bin/bash
# setup the TUN device tun$1 as default gateway for ipv6
# first make sure that the device exists, call tun_setup to set it up
TUN="tun$1"
ADDR="fec0::1"

if [ ! $(which ip) ]
then
    echo "you need iproute2 to setup ipv6 routing"
    exit 1
fi

# once we have an IP and a netmask we can use it as a real network interface
ifconfig $TUN $ADDR netmask 255.255.255.0
# check if the address is correct
ip route add default via $ADDR dev tun$1