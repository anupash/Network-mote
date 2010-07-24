#include "glue.h"
#include "motecomm.h"

struct TunHandlerInfo {
    int client_no;
    motecomm_t* mcomm;
};

void setup_routes(char const* const tun_name);

void laSet(laep_handler_t* this, la_t const address);

void tunReceive(fdglue_handler_t* that);

/** 
 * Call a shell script and check its result
 * 
 * @param script_cmd command to send
 * @param success print in case of success
 * @param err print in case of error
 * @param is_fatal exit if failing and 1, only error otherwise
 */
void callScript(char *script_cmd, char *success, char *err, int is_fatal);

void serialReceive(fdglue_handler_t* that);

serialif_t * createSerialConnection(char const *dev, mcp_t **mcp);

/** 
 * Processing data from the serial interface
 * 
 * @param that 
 * @param payload 
 */
void serialProcess(struct motecomm_handler_t *that, payload_t const payload);