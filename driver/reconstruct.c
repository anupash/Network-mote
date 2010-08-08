/**
 * Module that reconstructs the splitted data given in input.
 * We use a global circular array to store every possible "conversation".
 * This array contains the chunks we're temporary building with
 * some additional informations.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "reconstruct.h"
#include "chunker.h"
#include "tunnel.h"
#include "compress.h"
#include "structs.h"

#define POS(x) (x % MAX_RECONSTRUCTABLE)

typedef long unsigned bitmask_t;

typedef struct {
    int seq_no;
    // bitmaks of chunks still missing
    bitmask_t missing_bitmask;
    // That is the max size of the theoretically completed packet
    stream_t chunks[MAX_FRAME_SIZE];
    int tot_size;
    bool is_compressed;
} packet_t;

// Statistic variables
unsigned long started_pkts = 0;
unsigned long finished_pkts = 0;

static packet_t temp_packets[MAX_RECONSTRUCTABLE];
static void (*send_back)(payload_t completed);

/** 
 * @param seq_no sequential number to look for
 * 
 * @return NULL if not found, the pointer if found
 *         It can only returns null if that seq_no has been already overwritten
 */
packet_t *get_packet(int seq_no) {
    packet_t *found = &temp_packets[POS(seq_no)];
    if (found->seq_no == seq_no) {
        return found;
    }
    return NULL;
}

void fake_reconstruct_done(payload_t complete) {
    (void) complete;
    LOG_INFO("packet completed, not doing anything");
}

bool is_completed(packet_t *pkt) {
    return (pkt->missing_bitmask == 0);
}

bool check_if_same_chunk(packet_t *pkt1, packet_t *pkt2, int size) {
    return memcmp((void *) pkt1, (void *) pkt2, size);
}

void send_if_completed(packet_t *pkt) {
    // now we check if everything if the packet is completed and sends it back
    if (is_completed(pkt)) {
        LOG_DEBUG("packet seqno=%d completed, tot_size=%d", pkt->seq_no, pkt->tot_size);
        if(DEBUG)
            finished_pkts++;
        
        payload_t payload = {
            .len = pkt->tot_size,
            .stream = pkt->chunks
        };

#if COMPRESSION_ENABLED
        static stream_t compr_data[MAX_FRAME_SIZE];
        payload_t compressed = {
            .len = MAX_FRAME_SIZE,
            .stream = compr_data
        };
    
        if (pkt->is_compressed) {
            // we'll overwrite it when done
            payload_decompress(payload, &compressed);
            // should we alloc - memcpy - free instead?
            copy_payload(&compressed, &payload);
        }
#endif
        send_back(payload);
    }
}


/** 
 * initializing a temporary reconstruction packet
 * resetting also the memory
 * 
 * @param pkt 
 */
void init_temp_packet(packet_t* const pkt) {
  *pkt = (packet_t){
    .seq_no = -1,
    .missing_bitmask = -1ul,
    .tot_size = 0,
    .is_compressed = true
  };

  memset((void*)(pkt->chunks), 0, MAX_FRAME_SIZE * sizeof(stream_t));
}

/** 
 * Initializing the reconstruction module, setting to a default value
 * the values of the packet
 * 
 * @param callback callback function which will be called when the packet is completed
 */
void init_reconstruction(void (*callback)(payload_t completed)) {
    LOG_DEBUG("Initialising the reconstruction");

    send_back = callback;
    if (!callback) {
        send_back = fake_reconstruct_done;
        LOG_WARNING("Installing useless callback for completed packets.\n");
    }

    for (int i = 0; i < MAX_RECONSTRUCTABLE; i++) {
        init_temp_packet(temp_packets + i);
    }
}

/** 
 * Add a new chunk to the list of temp
 * 
 * @param data 
 */
void add_chunk(payload_t data) {
    // TODO: add another check of the length of the data given in
    assert(data.len <= sizeof(myPacket));
    assert(data.len >= sizeof(myPacketHeader));

    myPacket *original = malloc(sizeof(myPacket));
    memcpy(original, data.stream, sizeof(myPacket));

    int seq_no = get_seq_no(original);
    int ord_no = get_ord_no(original);
    
    // just for readability
    packet_t *pkt = &temp_packets[POS(seq_no)];
    
    if (pkt->seq_no != seq_no) {
        LOG_DEBUG("Overwriting or creating new packet at position %d", POS(seq_no));
        
        if (DEBUG)
            started_pkts++;
        
        pkt->is_compressed = is_compressed(original);
        // resetting to the initial configuration
        pkt->missing_bitmask = (1ul << get_parts(original)) - 1;
        pkt->seq_no = seq_no;
        pkt->tot_size = 0;
    }

    // all the chunks of the same packet are compressed OR not compressed
    if (pkt->is_compressed != is_compressed(original))
        LOG_WARNING("inconsistent compression flag found");

    LOG_DEBUG("Adding chunk (seq_no: %d, ord_no: %d, parts: %d, missing bitmask: %lu)", seq_no, ord_no, get_parts(original), pkt->missing_bitmask);

    // getting the real data of the packets
    int size = get_size(original, data.len);
    pkt->tot_size += size;

    memcpy(pkt->chunks + (MAX_CARRIED * ord_no), original->payload, size);
    
    // remove the arrived packet from the bitmask
    bitmask_t new_bm = (pkt->missing_bitmask) & ~(1ul << ord_no);

    if (new_bm == pkt->missing_bitmask) {
        LOG_WARNING("adding twice the same chunk");
        // the other one is at position POS(seq_no)
        if (check_if_same_chunk(pkt, &temp_packets[POS(seq_no)], sizeof(packet_t))) {
            // check if really the same one
            LOG_WARNING("REALLY THE SAME CHUNK");
        }
        
    } else  {
        // don't really need to even check for completion if it's a duplicate chunk
        pkt->missing_bitmask = new_bm;
        send_if_completed(pkt);
    }
    free(original);
}

stream_t *get_chunks(int seq_no) {
    packet_t *pkt = get_packet(seq_no);
    if (pkt)
        return pkt->chunks;

    return NULL;
}

/** 
 * Prints some statistical information about how many packets were completed.
 * 
 */
void print_statistics(void){
    LOG_NOTE("%lu packets were recognized and %lu were really sent (%f%%).", 
             started_pkts, finished_pkts, ((finished_pkts*100.0)/started_pkts));
}
