/**
 * @file   RoutingModuleP.nc
 * @author Oana Comanici, Ignacio Avellino, Anupam Ashish
 * 
 * @brief  This module implements the routing functionality between motes.
 *
 */

#include "RoutingModule.h"


generic module RoutingModuleP() {
  uses {
    // standard interfaces 
    interface Leds;
    
    // Radio interfaces
    interface AMSend as RadioSend;
    interface Receive as RadioReceive;
    
    // Packet interfaces
    interface Packet;
    interface AMPacket;
    
    // Timer interfaces
    interface Timer<TMilli> as TimerBeacon;
    interface Timer<TMilli> as TimerRoutingUpdate;
    interface Timer<TMilli> as TimerNeighborsAlive;
  }
}

implementation {
  /*************/
  /* Variables */
  /*************/
  
  // the routing table as an array of records
  routing_table_t routingTable[MAX_NUM_RECORDS];
  uint8_t noOfNeighbours;

  // the number of records of the routing table
  uint8_t noOfRoutes;
  message_t pkt;
  
  // whether radio is busy or available for transmission
  bool radioBusy = FALSE; 
  
  /*********/
  /* Tasks */
  /*********/
  
  /**
   * Task for broadcasting the beacon
   */
  task void sendBeacon() {
    if (!radioBusy) {
      beacons_t* beaconpkt = (beacons_t*)(call Packet.getPayload(&pkt, sizeof(beacons_t)));
      
      beaconpkt->node_id = TOS_NODE_ID;     // Node that created the packet			
      
      if (call RadioSend.send[AM_BEACON](AM_BROADCAST_ADDR, &pkt, sizeof(beacons_t)) == SUCCESS)
	radioBusy = TRUE;
      else
	post sendBeacon();
    }
    else
      post sendBeacon();
  }

  /**
   * Task for sending the routing updates to the neighbors
   */
  task void sendRoutingUpdate() {
    uint8_t i;
    if (!radioBusy) {
      routing_update_t* r_update_pkt = (routing_update_t*)(call Packet.getPayload(&pkt, sizeof(routing_update_t)));
      
      r_update_pkt->node_id = TOS_NODE_ID;
      r_update_pkt->num_of_records = noOfRoutes;			
      
      // routes from the routing table
      for (i = 0; i < noOfRoutes; i++) {
	r_update_pkt->records[i].node_id = routingTable[i].node_id;
	r_update_pkt->records[i].metric = routingTable[i].metric;
      }

      if (call RadioSend.send[AM_ROUTING_UPDATE](AM_BROADCAST_ADDR, &pkt, sizeof(routing_update_t)) == SUCCESS)
	radioBusy = TRUE;
      else
	post sendRoutingUpdate();
    }
    else
      post sendRoutingUpdate();
  }  
  
  /*************/
  /* Functions */
  /*************/
  
  /**
   * Initialize variables and timers of the routing module
   */
  void initRouting() {
    
    // start the timers for the beacon and for the routing updates
    call TimerBeacon.startPeriodic(2000);
    call TimerRoutingUpdate.startPeriodic(10000);
    
    // start timer for checking dead neighbors
    call TimerNeighborsAlive.startPeriodic(1000);
    
    // initialize routing table variables
    noOfRoutes = 0;
  }

  /**
   * Recalculate best paths after a topology change
   */
  void recalculateBestPaths() {
    ///TODO for each route, recalculate metric and hop count
  }

  /**
   * Process the information received in a beacon (add a new neighbor or confirm existing ones)
   * 
   * @param beaconMsg the beacon message received
   * @param beaconAddr the address if the node sending the beacon
   * 
   */
  void processBeacon(beacons_t* beaconMsg, am_addr_t beaconAddr) {
    bool isAlreadyNeighbor = FALSE;
    uint8_t i;
    
    for (i = 0; i < noOfRoutes; i++)
      if (routingTable[i].node_id == beaconMsg->node_id) {           // if a route already exists, reset the timeout
	routingTable[i].timeout = MAX_TIMEOUT;
	isAlreadyNeighbor = TRUE;
	break;
      }
      
    if (!isAlreadyNeighbor) {                                        // else, add a new neighbor to the routing table
      noOfRoutes++;
      routingTable[noOfRoutes - 1].node_id = beaconMsg->node_id;
      routingTable[noOfRoutes - 1].node_addr = beaconAddr;
      routingTable[noOfRoutes - 1].metric = 1;
      routingTable[noOfRoutes - 1].nexthop = TOS_NODE_ID;
      routingTable[noOfRoutes - 1].timeout = MAX_TIMEOUT;
      
      // if changes in the topology have occurred, recalculate paths and send updates
      recalculateBestPaths();
      post sendRoutingUpdate();
    }
  }

  /**
   * Process the information received in a routing update
   * 
   * @param routingUpdateMsg the beacon message received
   * @param beaconAddr the address if the node sending the beacon
   * 
   */
  void processRoutingUpdate(routing_update_t* routingUpdateMsg, am_addr_t sourceAddr) {
    
    uint8_t i, j;
    bool isAlreadyInTable = FALSE;
    
    // For each entry in the routing update received, check if this entry exists in the routing table and update it or create it
    uint8_t senderNodeId = routingUpdateMsg->node_id;
    uint8_t noOfRoutesUpdate = routingUpdateMsg->num_of_records;
    routing_record_t* updateRecords = routingUpdateMsg->records;
    
    for (i = 0; i < noOfRoutesUpdate; i++) {
      for (j = 0; j < noOfRoutes; j++) {                       
	// If there is an entry, check if the new route is better and update the next hop & metric
	if (routingTable[i].node_id == updateRecords[i].node_id && routingTable[i].metric > updateRecords[i].metric + 1) { 
	  routingTable[i].nexthop = senderNodeId;
	  routingTable[i].metric = updateRecords[i].metric + 1;
	}
	else {                                                         // If there is not an entry, create one.
	  if (noOfRoutes < MAX_NUM_RECORDS)
	    noOfRoutes++;
	  else return;
	  routingTable[noOfRoutes - 1].node_id = updateRecords[i].node_id;
	  routingTable[noOfRoutes - 1].node_addr = sourceAddr;
	  routingTable[noOfRoutes - 1].metric = updateRecords[i].metric + 1;
	  routingTable[noOfRoutes - 1].nexthop = senderNodeId;
	  routingTable[noOfRoutes - 1].timeout = MAX_TIMEOUT;
        }
      }
    }
  }

  /**********/
  /* Events */
  /**********/
  
  /**
   * Called when the timer for the beacon expires.
   * When this timer is fired, the mote broadcasts a beacon
   * 
   * @see tos.interfaces.Timer.fired
   */
  event void TimerBeacon.fired() {
    post sendBeacon();
  }
  
  /**
   * Called when the timer for the routing updates expires.
   * When this timer is fired, the mote sends a distance vector version of its
   * routing table to its neighbors (node id and metric)
   * 
   * @see tos.interfaces.Timer.fired
   */
  event void TimerRoutingUpdate.fired() {
    post sendRoutingUpdate();
  }
  
  /**
   * Called when the timer for the routes expires.
   * When this timer is fired, the timeout value of each 
   * route is decreased by one and the routes with timeout
   * 0 are removed from the routing table.
   * 
   * @see tos.interfaces.Timer.fired
   */
  event void TimerNeighborsAlive.fired() {
    uint8_t i, j;
    
    for (i = 0; i < noOfRoutes; i++) {
      routingTable[i].timeout--;
      // if the timeout becomes 0, remove the route from the routing table
      if (routingTable[i].timeout == 0) {
	for (j = i; j < noOfRoutes - 1; j++)
	  routingTable[j] = routingTable[i + 1];
	noOfRoutes--;
      }
    }
  }
  
  /**
   * Called when the radio interface is done sending a message.
   * 
   * @see tos.interfaces.AMSend.sendDone
   */
  event void RadioSend.sendDone[am_id_t id](message_t* msg, error_t error) {
    if (&pkt == msg)
      radioBusy = FALSE;
  }

  /**
  * Called when a message is received through the radio interface.
  * 
  * @see tos.interfaces.Receive.receive
  */
  event message_t* RadioReceive.receive[am_id_t id](message_t* msg, void* payload, uint8_t len) {
    
    beacons_t* receivedBeacon;
    routing_update_t* receivedRoutingUpdate;
    am_addr_t receivedBeaconAddr, receivedUpdateAddr;
    uint16_t msgType;
    
    // discard if not a valid message
    if (len != sizeof(beacons_t) && len != sizeof(routing_update_t))
      return msg;
    
    // get the type of message
    msgType = call AMPacket.type(msg);
    
    switch (msgType) {
      
      case AM_BEACON:
	receivedBeaconAddr = call AMPacket.source(msg);
	receivedBeacon = (beacons_t*) payload;
	processBeacon(receivedBeacon, receivedBeaconAddr);
	break;
      
      case AM_ROUTING_UPDATE:
	receivedUpdateAddr = call AMPacket.source(msg);
	receivedRoutingUpdate = (routing_update_t*) payload;
	processRoutingUpdate(receivedRoutingUpdate, receivedUpdateAddr);
	break;
      
      default: ;
    }
  }
}