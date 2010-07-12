#!/usr/bin/env python
"""
Take some data, send it to the device
"""

from scapy.all import *
# from TOSSIM import Tossim, SerialForwarder, Throttle
import os

TOSROOT = os.getenv("TOSROOT")
if TOSROOT is None:
    print "you need at least to setup your $TOSROOT variable correctly"
    sys.exit(1)

else:
    sdk = os.path.join(TOSROOT, "suppport", "sdk", "python")
    sys.path.append(sdk)

from tinyos.tossim.TossimApp import NescApp


# s.sendto(MAGIC_WORD, peer)


# setup the correct route via the created device
def setup_device(mode='tun'):
    # creating a tun device and sending data on it
    TUNSETIFF = 0x400454ca
    IFF_TUN   = 0x0001
    IFF_TAP   = 0x0002

    if mode == 'tap':
        TUNMODE = IFF_TAP
    else:
        TUNMODE = IFF_TUN

    f = os.open("/dev/net/tun", os.O_RDWR)
    ifs = ioctl(f, TUNSETIFF, struct.pack("16sH", "toto%d", TUNMODE))
    ifname = ifs[:16].strip("\x00")
    # s = socket(AF_INET, SOCK_DGRAM)
    print "Allocated interface %s. Configure it and use it" % ifname


# conf.route6.add