/**
 * Macro to see if we're working on OSX is __APPLE__
 */

// Includes
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <termios.h>
#include <arpa/inet.h>

// Standard libraries
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <stdio.h>

// Functions for using a tunnel device
#include "tunnel.h"
// For adding an entry to the routing tables
#include "routing.h"
// Include the serial forwarder
//#include <serialsource.h>

// our own declarations
#include "client.h"

#include "motecomm.h"
#include "chunker.h"

#include "glue.h"
#include "../shared/structs.h"

#ifdef CLIENT
#define CLIENT_NO 0

#elif GATEWAY
#define CLIENT_NO get_client_no()

#endif

// a wrapper for mcp::receive that will be understood by the fdglue module
void serialReceive(fdglue_handler_t* that) {
    mcp_t* this = (mcp_t*)(that->p);
    this->getComm(this)->read(this->getComm(this));
}

// TODO: change me, this will have to return the client we work on on the gateway
int get_client_no() {
    return 0;
}

struct TunHandlerInfo {
    int fd;
    ifp_t* ifp;
    motecomm_t* mcomm;
};

void tunReceive(fdglue_handler_t* that) {
    printf("tunReceive called\n");
    
    struct TunHandlerInfo* this = (struct TunHandlerInfo*)(that->p);
    static stream_t buf[MAX_FRAME_SIZE];
    memset(buf,0,MAX_FRAME_SIZE);
    int size = tunRead(CLIENT_NO, (char*)buf,MAX_FRAME_SIZE);
    assert(size);
    static int seqno = 0;
    ++seqno;
    payload_t payload = {.stream = buf, .len = size};
    ipv6Packet ipv6;
    unsigned sendsize = 0;
    int no_chunks = needed_chunks(size);
    char chunks_left;
    do{
        chunks_left = genIpv6Packet(&payload,&ipv6,&sendsize,seqno, no_chunks);
        assert(sendsize);
        
        printf("Sending chunk with size %u\n", sendsize);
        unsigned counter = sendsize;
        unsigned char *char_data = (unsigned char*)&ipv6;
        while(counter--){
            printf("%02X ", (unsigned)*char_data++);
        }
        printf("\n");
        
        // Use the raw packet for now...
        //this->ifp->send(this->ifp,(payload_t){.stream = (stream_t*)&ipv6, .len = sendsize});
        this->mcomm->send(this->mcomm, (payload_t){.stream = (stream_t*)&ipv6, .len = sendsize});
        
        sendsize = 0;
    }while (chunks_left); 
    
}

la_t localAddress = DEFAULT_LOCAL_ADDRESS;

void laSet(laep_handler_t* this, la_t const address) {
    (void)this;
    localAddress = address;
}

void usage() {
    fprintf(stderr, "./tuntest <device>\n");
    exit(EX_USAGE);
}

int main(int argc, char** argv) {
    if (argc != 2) {
        usage();
    }

    (void)argc;
    (void)argv;

    char tun_name[IFNAMSIZ];
    tunSetup(TUNTAP_INTERFACE);

    // a new device should be opened!
    tun_name[0] = 0;    
    // create the tap-device
    // only in the gateway the first argument should be != 0
    int tun_fd = tunOpen(CLIENT_NO, tun_name);
    if (tun_fd < 1) {
        printf("Could not create tunnel device. Fatal.\n");
        return 1;
    } else {
        printf("created tunnel device: %s\n", tun_name);
    }

    fflush(stdout);

    // Run the setup script for the tunnel
    char script_cmd_p[30] = "sh route_setup.sh ";
    char *script_cmd = (char *)malloc(strlen(script_cmd_p) + IFNAMSIZ); 
    script_cmd = strcat(script_cmd_p, tun_name);
    int err = system(script_cmd);
    if (err != 0){
        perror("Running setup script");
    }else{
        printf("Tunnel setup successful!\n");
    }

    /* uint8_t buf[sizeof(struct split_ip_msg) + INET_MTU]; */
    /* struct split_ip_msg *msg = (struct split_ip_msg *)buf; */

    fdglue_t fdg;
    fdglue(&fdg);
    char mote[] = "telosb";
    char const* dev = argv[1];
    serialif_t* sif = NULL;
    mcp_t* mcp = openMcpConnection(dev,mote,&sif);
    ifp_t _ifp;
    ifp(&_ifp,mcp);
    laep_t _laep;
    laep(&_laep,mcp);
    _laep.setHandler(&_laep,LAEP_REPLY,(laep_handler_t){.handle = laSet, .p = NULL});
    if (mcp) {
        printf("Connection to %s over device %s opened.\n",mote,dev);
    } else {
        printf("There was an error opening the connection to %s over device %s.\n",mote,dev);
    }
    fflush(stdout);
    struct TunHandlerInfo thi = {.fd = tun_fd, .ifp = &_ifp, .mcomm = mcp->getComm(mcp)};
    fdg.setHandler(&fdg,sif->fd(sif),FDGHT_READ,(fdglue_handler_t) {
            .p = mcp,
                .handle = serialReceive},FDGHR_APPEND);
    fdg.setHandler(&fdg,tun_fd,FDGHT_READ,(fdglue_handler_t){
            .p = &thi,
                .handle = tunReceive},FDGHR_APPEND); //TODO

    unsigned lcount = 0;
    for (;;) {
        printf("listening %d ...\n",lcount++);
        fflush(stdout);
        fdg.listen(&fdg,5*60);
    }
    
    /* int size = 200; */
    /* char *buff = malloc(size); */
    /* int len; */
    /* while(1) { */
    /*     memset(buff, 0, size); */
    /*     len = tun_read(tun_fd, buff, size); */
    /*     if (len > 0) { */
    /*         printf("got a message of length %d\n", len); */
    /*     } else { */
    /*         perror("not receiving anything\n"); */
    /*     } */
    /* } */
    /* return 0; */
}
