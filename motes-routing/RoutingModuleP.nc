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
    interface Timer<Milli> as TimerBeacon;
    interface Timer<Milli> as TimerRoutingUpdate;
    interface Timer<Milli> as TimerNeighborsAlive;
  }
  
  provides {
    interface Routing;
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

  
  /*************/
  /* Functions */
  /*************/
  
  /**
   * Initialize variables and timers of the routing module
   */
  void initRouting() {
    
    // start the timers for the beacon and for the routing updates
    TimerBeacon.startPeriodic(2000);
    TimerRoutingUpdate.startPeriodic(10000);
    
    // start timer for checking dead neighbors
    TimerNeighborsAlive.startPeriodic(1000);
    
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
    
    for (uint8_t i = 0; i < noOfRoutes; i++)
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
   * 
   */
  void processRoutingUpdate(routing_update_t* routingUpdateMsg) {
    ///TODO get each record and update the routing table
  }

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
    if (!radioBusy) {
      routing_update_t* r_update_pkt = (routing_update_t*)(call Packet.getPayload(&pkt, sizeof(routing_update_t)));
      
      r_update_pkt->node_id = TOS_NODE_ID;
      r_update_pkt->num_of_records = noOfRoutes;			
      
      // routes from the routing table
      for (uint8_t i = 0; i < noOfRoutes; i++) {
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
    post broadcastBeacon();
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
   * Called when the radio interface is done sending a message.
   * 
   * @see tos.interfaces.AMSend.sendDone
   */
  event void RadioSend.sendDone[am_id_t id](message_t* msg, error_t error)) {
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
    am_addr_t receivedBeaconAddr;
    
    // discard if not a valid message
    if (len != sizeof(beacons_t) && len != sizeof(routing_update_t))
      return msg;
    
    // get the type of message
    uint16_t msgType = call AMPacket.type(msg);
    
    switch (msgType) {
      
      case AM_BEACON:
	receivedBeacon = (beacons_t*) payload;
	receivedBeaconAddr = call AMPacket.source(msg);
	processBeacon(receivedBeacon, receivedBeaconAddr);
	break;
      
      case AM_ROUTING_UPDATE:
	receivedRoutingUpdate = (routing_update_t*) payload;
	processRoutingUpdate(receivedRoutingUpdate);
	break;
      
      default: ;
    }
  }
  
}
