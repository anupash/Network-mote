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
   * Initialize variables of the routing modules
   */
  void initRouting() {
    
    // start the timer for the beacon
    TimerBeacon.startPeriodic(2000);
  }
  
  
  
  
  
  
  
  
  
}
