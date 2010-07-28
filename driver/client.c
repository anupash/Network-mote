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
#include <stdio.h>

#include <sysexits.h>

#include "tunnel.h"
// our own declarations
#include "client.h"
#include "reconstruct.h"

#include "../shared/structs.h"
#include "setup.h"

#define CLIENT_NO 0

char notun = 0;

/** 
 * Setting up the routing table, which need iproute2 to work!!
 * 
 */
void setup_routes(char const* const tun_name) {
    char script_cmd[80] = "bash route_setup.sh ";
    strcat(script_cmd, tun_name);
    callScript(script_cmd, "tunnel succesfully set up", "routing setting up", 1);
}

int startClient(char const *dev) {

    if (!notun) {
        // on the server instead could create many
        char tun_name[IFNAMSIZ];
        tunSetup(TUNTAP_INTERFACE);

        // a new device should be opened!
        tun_name[0] = 0;    
        // create the tap-device

        // it will exit abruptly if it doesn't open it correctly
        tunOpen(CLIENT_NO, tun_name);

        fflush(stdout);

        setup_routes(tun_name);
    }

    // wrapper for select
    fdglue_t fdg;
    fdglue(&fdg);
    
    mcp_t *mcp;
    serialif_t *sif = createSerialConnection(dev, &mcp);

    fflush(stdout);
    struct TunHandlerInfo thi = {
        .client_no = CLIENT_NO,
        .mcomm = mcp->getComm(mcp)
    };

    fdglue_handler_t hand_sif = {
        .p = mcp,
        .handle = serialReceive
    };
    fdglue_handler_t hand_thi = {
        .p = &thi,
        .handle = tunReceive
    };

    fdg.setHandler(&fdg, sif->fd(sif), FDGHT_READ, hand_sif, FDGHR_APPEND);
    if (!notun)
      fdg.setHandler(&fdg, getFd(CLIENT_NO), FDGHT_READ, hand_thi, FDGHR_APPEND);


    for (;;) {
        //static unsigned lcount = 0;
        //printf("listening %d ...\n",lcount++);
        printStatistics();
        fflush(stdout);
        fdg.listen(&fdg, 5 * 60);
    }
}

void usage(char* name) {
    fprintf(stderr, "%s <device>\n",name);
    exit(EX_USAGE);
}

int main(int argc, char *argv[]) {

    int k = 43;
    DUMP_INT(k);
    return 0;
    /*if (argc != 2) {
        usage(argv[0]);
    }*/
    notun = (argc >= 3 && 0 == strcmp(argv[2],"notun"));

    char const* dev = argv[1];

    startClient(dev);
    return 0;
}
