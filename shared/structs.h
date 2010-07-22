#ifndef __STRUCTS_H
#define __STRUCTS_H

// measures in bytes
#define SIZE_IPV6_HEADER 40
// For the usage of additional headers MAX_CARRIED has to be smaller
#define MAX_CARRIED (TOSH_DATA_LENGTH - sizeof(struct ipv6PacketHeader))
//#define MAX_CARRIED (TOSH_DATA_LENGTH - sizeof(ipv6PacketHeader) - MCP_HEADER_BYTES - 5)
#define TOT_PACKET_SIZE(payload_len) (sizeof(struct ipv6PacketHeader) + payload_len)
#define PAYLOAD_LEN (MAX_CARRIED - sizeof(ipv6Packet))


#define TUNTAP_INTERFACE IFF_TUN

#if TUNTAP_INTERFACE == IFF_TAP
#define MAX_FRAME_SIZE 2048
#elif TUNTAP_INTERFACE == IFF_TUN
#define MAX_FRAME_SIZE 65536
#else
#error "Unsupported tun/tap interface."
#endif


#include <ip.h>

typedef unsigned char stream_t;
typedef unsigned int streamlen_t;

typedef struct {
  stream_t const* stream;
  streamlen_t len;
} payload_t;

typedef struct in6_addr in6_src;
typedef struct in6_addr in6_dst;

// just for more ease of writing
typedef struct sockaddr_in6 sockaddr_in6;
typedef struct ip6_hdr ip6_hdr;

// TODO: add another field to keep the total number of parts needed
// also the internal struct should be packed
typedef struct myPacketHeader {
    uint8_t seq_no;
    uint8_t ord_no;
    uint8_t parts;
} __attribute__((__packed__)) myPacketHeader;

// FIXME: ipv6 header is not needed inside here anymore
// only the final ipv6 packet must be "__packed__".
typedef struct ipv6Packet {
    // sent data ...
    struct ipv6PacketHeader{ 
        struct ip6_hdr ip6_hdr;
        myPacketHeader packetHeader;
    } __attribute__((__packed__)) header;

    stream_t payload[MAX_CARRIED];
} __attribute__((__packed__)) ipv6Packet;

#endif

