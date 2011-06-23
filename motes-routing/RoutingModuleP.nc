/**
 * @file   RoutingModuleP.nc
 * @author Oana Comanici, Ignacio Avellino, Anupam Ashish
 * 
 * @brief  This module implements the routing functionality between motes.
 *
 */

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
  
  // the routing table as a linked list of records
  routing_table_t* routingTable;
  
  // the number of records of the routing table
  uint8_t noOfRoutes;



  /*************/
  /* Functions */
  /*************/
  
  /**
   * Initialize variables of the routing module
   * 
   */
  void initRouting() {
    
    // start the timers for the beacon and for the routing updates
    TimerBeacon.startPeriodic(2000);
    TimerRoutingUpdate.startPeriodic(10000);
    
    // initialize routing table variable
    routingTable = NULL;
    noOfRoutes = 0;
  }
  

  /*********/
  /* Tasks */
  /*********/
  
  /**
   * Task for broadcasting the beacon
   */
  task void broadcastBeacon() {
    
  }

  /**
   * Task for sending the routing updates to the neighbors
   */
  task void sendRoutingUpdate() {
    
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
    
  }

  /**
  * Called when a message is received through the radio interface.
  * 
  * @see tos.interfaces.Receive.receive
  */
  event message_t* RadioReceive.receive[am_id_t id](message_t* msg, void* payload, uint8_t len) {
    
  }
  
  
}
