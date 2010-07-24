#ifndef _RECONSTRUCT_H
#define _RECONSTRUCT_H

#include "structs.h"

// max number of packets kept in the temporary structure for reconstruction
#define MAX_RECONSTRUCTABLE 4

// this could be computed somehow from the MAX_FRAME_SIZE and the size carried
#define MAX_CHUNKS 100

#include "util.h"

typedef struct {
    int seq_no;
    // bitmaks of chunks still missing
    int missing_bitmask;
    // That is the max size of the theoretically completed packet
    stream_t chunks[MAX_FRAME_SIZE];
    int tot_size;
} packet_t;


/** 
 * Initialize the reconstruction of packets
 * 
 * @param callback takes a function which will send back packets when they're completed
 */
void initReconstruction(void (*callback)(payload_t completed));

/** 
 * Adding a new chunk of data
 * 
 * @param data 
 */
void addChunk(payload_t data);


/** 
 * @param seq_no sequential number of the packet
 * 
 * @return pointer to the chunks
 */
stream_t *getChunks(int seq_no);

void makeIpv6Packet(ipv6Packet *ip6_pkt, int seq_no, int ord_no, int parts, stream_t *payload, int len);

#endif
