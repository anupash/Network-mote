/**
 * Serial implementation for the pc side.
 * @date some day in mid 2010
 * @author Oscar Dustmann
 */
#ifndef _SERIALIF_H
#define _SERIALIF_H

#include <serialsource.h>
#include <stdint.h>
#include <stdbool.h>

#ifndef SERIAL_FORCE_ACK_SLEEP_US
#define SERIAL_FORCE_ACK_SLEEP_US 500
#endif

// note: the serialif_t type is defined in motecomm.h for historical and not so obvious reasons

/****** copied from serialsource.c ******/
/****** DO NOT MODIFY! ******/
#define BUFSIZE 256
#define MTU 256
struct serial_source_t {
#ifndef LOSE32
  int fd;
#else
  HANDLE h_comm;
#endif
  bool non_blocking;
  void (*message)(serial_source_msg problem);

  /* Receive state */
  struct {
    uint8_t buffer[BUFSIZE];
    int bufpos, bufused;
    uint8_t packet[MTU];
    bool in_sync, escaped;
    int count;
    struct packet_list *queue[256]; // indexed by protocol
  } recv;
  struct {
    uint8_t seqno;
    uint8_t *escaped;
    int escapeptr;
    uint16_t crc;
  } send;
};
/****** END (serialsource.c) ******/

// local recreation of the message_t header
// XXX this is some sort of hack, and we should probably just include message.h
// but that struct is hardware dependent in tinyos, which makes it hard to include it.
struct message_header_mine_t {
    uint8_t amid;
    uint16_t destaddr;
    uint16_t sourceaddr;
    uint8_t msglen;
    uint8_t groupid;
    uint8_t handlerid;
}  __attribute__((packed));

#endif
