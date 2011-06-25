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
  	uint8_t noOfNeighbours;

  	// the number of records of the routing table
  	uint8_t noOfRoutes;
	message_t pkt;                ///<
	bool busy = FALSE;            ///< Radio is busy or available for transmission
	
		

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
  
	task void sendBeacon(){
		if(!busy){
			beacons_t* beaconpkt = (beacons_t*)(call Packet.getPayload(&pkt, sizeof (beacons_t)));
			brpkt->node_id = TOS_NODE_ID;     // Node that created the packet			
			if(call RadioSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(beacons_t))==SUCCESS) {
				busy = TRUE;
			}
		}	
	}	

	task void sendRoutingUpdate(){
		if(!busy){
			routing_update_t* r_update_pkt = (routing_update_t*)(call Packet.getPayload(&pkt, sizeof (routing_update_t)));
			r_update_pkt->node_id = TOS_NODE_ID;
			r_update_pkt->num_of_records = TOS_NODE_ID;			
			if(call RadioSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(routing_update_t))==SUCCESS) {
				busy = TRUE;
			}
		}		
	}  
}
