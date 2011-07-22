/**
 * @file   SimpleMoteAppP.nc
 * @author Marius Grysla, Oscar Dustman, Andrea Crotti, Anupam Ashish, Ignacio Avellino, Oana Comanici
 * @date   Fri Aug 13 18:33:36 2010
 * 
 * @brief  Implementation of the MOTENET mote program.
 * 
 */

#include "SimpleMoteApp.h"
#include "printf.h"
#include "string.h"

module SimpleMoteAppP {
  uses {
    // Standard interfaces
    interface Boot;
    interface Leds;

    // Radio interfaces
    interface SplitControl as RadioControl;
    // Send and receive interfaces for the IP packets
    interface AMSend as IPRadioSend;
    interface Receive as IPRadioReceive;
    // Send and receive interfaces for the routing updates
    interface AMSend as RoutingRadioSend;
    interface Receive as RoutingRadioReceive;

    // Serial interfaces
    interface SplitControl as SerialControl;
    interface AMSend as SerialSend;
    interface Receive as SerialReceive;

    // Packet interfaces
    interface Packet;
    interface AMPacket;
    interface CC2420Packet;
    interface PacketAcknowledgements;

    // Routing interfaces
    interface Timer<TMilli> as TimerRoutingUpdate;
    interface Timer<TMilli> as TimerNeighborsAlive;
  }
}
implementation {

  /*****************************/
  /* General purpose variables */
  /*****************************/

  // A queue for every mote, in which we save the latest 16 messages to 
  // identify duplicates.
  // The higher byte will hold the sequential number, while the lower byte
  // will hold the number of the chunk.
  uint16_t queues[MAX_MOTES][PACKET_QUEUE_SIZE];
  // Array of pointers to the queues' heads.
  uint16_t *heads[MAX_MOTES];

  // The message that is used for serial acknowledgements.
  message_t ack_msg;
  
  // Variables used for radio sending task
  am_addr_t sR_dest;
  message_t sR_m;
  myPacketHeader sR_payload;
  uint8_t sR_len;
  uint16_t sR_type;
  uint8_t retransmissionCounter;
  
  // Variables used for serial sending task
  am_addr_t sS_dest;
  message_t sS_m;
  uint8_t sS_len;
  
  // Variables needed for debug purposes
  char debugMsg[100];
  
  /*************************/
  /* Variables for routing */
  /*************************/
  
  // the routing table as an array of records
  routing_table_t routingTable[MAX_MOTES][MAX_NUM_RECORDS];
  uint8_t noOfRoutes[MAX_MOTES];

  // table of alternative routes
/*  routing_table_t alternativePaths[MAX_MOTES][MAX_NUM_RECORDS];
  uint8_t noOfAlternativePaths[MAX_MOTES];*/
  
  message_t pkt;
  
  // whether Routing Radio is busy or available for transmission
  boolean routingRadioBusy; 
  // whether IP Radio is busy or available for transmission
  boolean IPRadioBusy; 

  /*************************/
  /* Function declarations */
  /*************************/

  /**
  * Print function for debugging purposes
  * 
  * @param msg The debug message to be displayed
  * 
  */
  void printDebugMessage(const char* msg);
  
  /**
  * Print Routing Tables for debugging purposes
  * 
  * @param destination Node for which the alternative paths has to be printed
  * 
  */
  void printRoutingTable(uint8_t mote);
  
  /**
  * Add a new path to a certain destination in the routingTable
  * 
  * @param destination The destination for which a new path should be added 
  * @param destination_addr The address of the destination
  * @param next_hop The next hop in the new path
  * @param hop_count The new hop count
  * @param link_quality The new link quality
  */
  void addNewPath(uint8_t destination, am_addr_t destination_addr, uint8_t next_hop, uint8_t hop_count, int8_t link_quality);
  
  /**
  * Test if one path is better than the other
  * 
  * @param new_hop_count The hop count of the new path
  * @param old_hop_count The hop count of the old path
  * @param new_link_quality The link quality of the new path
  * @param old_link_quality The link quality of the old path
  * 
  * @return Return if the new path is better than the old one
  */
  boolean isPathBetter(uint8_t new_hop_count, uint8_t old_hop_count, int8_t new_link_quality, int8_t old_link_quality);
  
  /**
  * Removing an entry from the routing table
  * 
  * @param destination The destination for which a route should be removed
  * @param next_hop The next hop identifying the route that should be removed; if it is -1, remove all routes to destination
  */
  void removeFromRoutingTable(uint8_t destination, uint8_t next_hop);
  
  
 /**
  * Choose next available path for sending a packet to a destination
  * 
  * @param destination The destination to which th packet should be sent
  * @param counter Identifies the alternative route to be used
  * 
  * @return true if there was an available path to choose, false otherwise
  */
  bool chooseNextAvailablePath(uint8_t destination, uint8_t counter);
  
  
  /*********/
  /* Tasks */
  /*********/

  /** 
  * A task for sending radio messages
  */
  task void sendRadio(){
      
    // request acknowledgement for the packet to be sent
    call PacketAcknowledgements.requestAck(&sR_m);
    
    switch (sR_type) {
      
      case AM_IP: 
	if (!IPRadioBusy) {
	  if (call IPRadioSend.send(sR_dest, &sR_m, sR_len) == SUCCESS) {
	    IPRadioBusy = TRUE;
	    
	    //sprintf(debugMsg, "[sendRadio] AM_IP sent from %u to %u\n",TOS_NODE_ID, sR_dest);
	    printDebugMessage(debugMsg);
	  }
	  else
	    post sendRadio();
	}

	else
	  post sendRadio();
	
	break;
      
      case AM_ROUTING_UPDATE:
	if (!routingRadioBusy) {
	  if (call RoutingRadioSend.send(sR_dest, &sR_m, sR_len) == SUCCESS) {
	    routingRadioBusy = TRUE;
	    
	    //sprintf(debugMsg, "[sendRadio] AM_ROUTING_UPDATE sent from %u to %u\n",TOS_NODE_ID,sR_dest);
	    printDebugMessage(debugMsg);
	  }
	  else
	    post sendRadio();
	}
	else
	  post sendRadio();
	
	break;
      default: ;
    }
  }

 /** 
  * A task for sending serial messages
  */
  task void sendSerial(){
      call SerialSend.send(sS_dest, &sS_m, sS_len);
  }

 /**
  * Sends an acknowledgement for the last packet over the serial.
  * An acknowledgement is just of an empty Active Message.
  */
  task void sendSerialAck(){
      //TODO: Does that work, or does TinyOS give us an error for the 0?
      call SerialSend.send(AM_BROADCAST_ADDR, &ack_msg, 0);
  }
  
  
  /*************/
  /* Functions */
  /*************/

   /**
    * Print function for debugging purposes
    */
  void printDebugMessage(const char* msg) {
    //printf(msg);
  }
   
   
  /**
    * Print Routing Tables for debugging purposes
    * 
    * @param mote Node for which the alternative paths has to be printed
    * 
  */
  void printRoutingTable(uint8_t mote){
    uint8_t i;
    char route[100];

    for(i=0; i < noOfRoutes[mote]; i++){
      //sprintf(route, "%s| %u, %u, %u", route, routingTable[mote][i].nexthop, routingTable[mote][i].hop_count, routingTable[mote][i].link_quality);
    }
    //sprintf(route,"RT [ %s ]\n",route);
    printDebugMessage(route);
  }
  
   /**
    * Initialize variables and timers of the routing module
    */
  void initRouting() {
    uint8_t i;
    
    // initialize routing table variables
    for (i = 0; i < MAX_MOTES; i++)
      noOfRoutes[i] = 0;
    routingRadioBusy = FALSE;
    IPRadioBusy = FALSE;

    // start the timer for the routing updates
    call TimerRoutingUpdate.startPeriodic(5000);
    
    // start timer for checking dead neighbors
    call TimerNeighborsAlive.startPeriodic(1000);
    //printfflush();
  }
  
   /** 
    * Test, whether an message signature is in the queue (was recently seen).
    * 
    * @param client The TOS_NODE_ID. Should be smaller that MAX_MOTES!!!
    * @param seq_no The sequential number of the message.
    * @param ord_no The chunk number.
    * 
    * @return 1, if the signature is contained, 0 otherwise.
    */
  boolean inQueue(am_addr_t client, seq_no_t seq_no, uint8_t ord_no){
      uint8_t i;
      uint16_t identifier;

      // Build identifier from seq_nr and ord_nr
      identifier = (((uint16_t) seq_no) << 8) | ord_no;

      //Position 0 of the queue reserved for the Gateway
      //THis is done because the size of queue limited to MAX_MOTES
      if (client == 254) client = 0;
      
      
      // Just loop over all elements
      for(i = 0; i < PACKET_QUEUE_SIZE; i++){
	  if(queues[client][i] == identifier){
	      return 1;
	  }
      }
      
      return 0;
  }

   /** 
    * Inserts a new message identifier into one of the queues.
    * 
    * @param client The TOS_NODE_ID. Should be smaller that MAX_MOTES!!!
    * @param seq_nr The sequential number of the message.
    * @param ord_nr The chunk number.
    */
  void addToQueue(am_addr_t client, seq_no_t seq_no, uint8_t ord_no){
      uint16_t identifier;

      // Build identifier from seq_nr and ord_nr
      identifier = (((uint16_t) seq_no) << 8) | ord_no;

      //Position 0 of the queue reserved for the Gateway
      //THis is done because the size of queue limited to MAX_MOTES
      if (client == 254) client = 0;

      if(heads[client] == &queues[client][PACKET_QUEUE_SIZE - 1]){
	  // We are at the end of the queue
	  heads[client] = queues[client];
	  *heads[client] = identifier;
      }else{
	  // Normal insertion
	  *(++heads[client]) = identifier;
      }
  }

 /**
  * Function for sending the routing updates to the neighbors
  */
  void sendRoutingUpdate() {
    uint8_t i;
    routing_update_t* r_update_pkt = (routing_update_t*)(call Packet.getPayload(&pkt, sizeof(routing_update_t)));
    
    r_update_pkt->node_id = TOS_NODE_ID;
    ///TODO decide on the number of records - if MAX_MOTES, then lower the value, otherwise it will not be transmitted
    r_update_pkt->num_of_records = MAX_MOTES;			
    
    // add best routes from the routing table
    for (i = 0; i < MAX_MOTES; i++) {
      r_update_pkt->records[i].node_id = routingTable[i][0].node_id;
      r_update_pkt->records[i].node_addr = routingTable[i][0].node_addr;
      r_update_pkt->records[i].hop_count = routingTable[i][0].hop_count;
      r_update_pkt->records[i].link_quality = routingTable[i][0].link_quality;
    }
    
    // broadcast the routing updates over the radio
    sR_dest = AM_BROADCAST_ADDR;
    sR_m = pkt;
    sR_len = sizeof(routing_update_t);
    sR_type = AM_ROUTING_UPDATE;
    post sendRadio();
  }  
  

 /**
  * Resolves the next hop for a message and forwards it
  * 
  * @param msg the message to be sent
  * @param myph the payload of the message to be sent
  * @param len the length of the message to be sent
  * 
  */
  void forwardPacket(message_t* msg, myPacketHeader* myph, uint8_t len) {
    
    am_addr_t nextHopAddress = 0;

    // If this mote is a node attatched to a PC, set the correct destination.
    if(TOS_NODE_ID == 1) myph->destination = 254;
    else if (TOS_NODE_ID == 254 ) myph->destination = 1;
    
    //sprintf(debugMsg, "[forwardPacket] At node= %u destination received = %u ", TOS_NODE_ID, myph->destination);
    printDebugMessage(debugMsg);

    // resolve next hop for destination
    if (noOfRoutes[myph->destination] > 0)
      nextHopAddress = routingTable[myph->destination][0].nexthop;
    else
      return;                      // drop the packet if there is no route for its destination
    
    // next, forward it
    sR_type = AM_IP;
    sR_dest = nextHopAddress; 
    sR_m = *msg; 
    sR_payload = *myph;
    sR_len = len;
    retransmissionCounter = 0;
    post sendRadio();
  }

 /**
  * Process the information received in a routing update
  * 
  * @param routingUpdateMsg the message with the routing updates
  * @param sourceAddr the address of the source nodes
  * 
  */
  void processRoutingUpdate(routing_update_t* routingUpdateMsg, am_addr_t sourceAddr, int8_t linkQuality) {

    uint8_t i;
    
    uint8_t senderNodeId = routingUpdateMsg->node_id;
    uint8_t noOfRoutesUpdate = routingUpdateMsg->num_of_records;
    routing_record_t* updateRecords = routingUpdateMsg->records;
    
    if((TOS_NODE_ID == 1 && senderNodeId == 254) || (TOS_NODE_ID == 254 && senderNodeId == 1))
      return;
    
    //DEBUG
    call Leds.led0Toggle();
    
    if (senderNodeId == 254)
      senderNodeId = 0;

    // add the sending node as a neighbor
    addNewPath(senderNodeId, sourceAddr, senderNodeId, 1, linkQuality);
    
    // then process the routing update records one by one
    for (i = 0; i < noOfRoutesUpdate; i++){
      addNewPath(updateRecords[i].node_id, updateRecords[i].node_addr /*TODO transmit it or leave it out - not correct*/, senderNodeId, updateRecords[i].hop_count + 1, (updateRecords[i].link_quality + linkQuality) / (updateRecords[i].hop_count + 1));
    }
    
  }
    

   /**
    * Add a new path to a certain destination in the routingTable
    * 
    * @param destination The destination for which a new path should be added 
    * @param destination_addr The address of the destination
    * @param next_hop The next hop in the new path
    * @param hop_count The new hop count
    * @param link_quality The new link quality
    */
  void addNewPath(uint8_t destination, am_addr_t destination_addr, uint8_t next_hop, uint8_t hop_count, int8_t link_quality) {
    uint8_t i, j, k;
    routing_table_t aux;
    boolean found = FALSE;
    boolean routeFound = FALSE;
    
    
    //sprintf(debugMsg, "[addNewPath()] ******** destination=%u nexthop=%u hopcount=%u \n",destination, next_hop, hop_count);      
    printDebugMessage(debugMsg);
    printRoutingTable(destination);
    
    // first check if the new path already exists
    for (i = 0; i < noOfRoutes[destination]; i++) {
      
      if (routingTable[destination][i].nexthop == next_hop) {
	//sprintf(debugMsg, "[addNewPath()] Found a route at i=%u\n",i);      
	//printDebugMessage(debugMsg);
      
	// if the exact same path and metric already exists, do nothing
	if (routingTable[destination][i].hop_count == hop_count &&
	    routingTable[destination][i].link_quality == link_quality){
	  ////sprintf(debugMsg, "[addNewPath()] Ignoring update because of same metric and path\n");      
	  //printDebugMessage(debugMsg);
	  return;
	}
	// else if the metric has changed 
	// check if the new metric is acceptable (link quality is above a certain threshold)
	// otherwise discard it
	if (link_quality < MIN_LINK_QUALITY) {
	  
	  //sprintf(debugMsg, "[addNewPath()] Removing because the link quality was unacceptable\n");      
	  //printDebugMessage(debugMsg);
	  removeFromRoutingTable(destination, next_hop);
	  return;
	}
	
	routeFound = TRUE;
	break;                     // same route is found but with different metric, stop searching further
      }
    }


    //sprintf(debugMsg, "[addNewPath()] routeFound = %s\n",routeFound?"TRUE":"FALSE");      
    //printDebugMessage(debugMsg);
    
    if (routeFound) {
      // update the existing metric and re-order the paths
      routingTable[destination][i].hop_count = hop_count;
      routingTable[destination][i].link_quality = link_quality;
      
      // find the first path (j) with a worse metric than this (i) 
      for (j = 0; j < noOfRoutes[destination] && j != i; j++) {
	if (isPathBetter(routingTable[destination][i].hop_count, routingTable[destination][j].hop_count,
	    routingTable[destination][i].link_quality, routingTable[destination][j].link_quality)) {
	  found = TRUE;
	  //sprintf(debugMsg, "[addNewPath()] First position with a worse metric=%u\n",j);      
	  //printDebugMessage(debugMsg);
	  break;
	}
      }
      
      if (found) {
	// re-order the paths according to metric
	aux = routingTable[destination][i];
      
	// if the route must be promoted
	if (j < i) {
	  // move j...i-1 to the right
	  for (k = i; k > j; k--)
	    routingTable[destination][k] = routingTable[destination][k-1];
	  
	  // insert i in j
	  routingTable[destination][j] = aux;
	}
	else {  // if the route must be degraded
	    //Note if i = j-1 they are already in correct position nothing to do, hence "for" loop skipped
	    // move i+1...j-1 to the left
	    for (k = i + 1; k < j; k++)
	      routingTable[destination][k - 1] = routingTable[destination][k];
	    // insert i in j-1
	    routingTable[destination][j-1] = aux;
	}
      }
      else {                   // this is the route with the worst metric, move it to the end and promote all before it
	aux = routingTable[destination][i];
	for (k = i; k < noOfRoutes[destination] - 1; k++)
	  routingTable[destination][k] = routingTable[destination][k + 1];
		
	routingTable[destination][noOfRoutes[destination] - 1] = aux; 
      }
    }

    // else the route wasn't found, so it will be added according to metric
    else {
      
      // find the first path (j) with a worse metric than the new one 
      for (j = 0, found = FALSE; j < noOfRoutes[destination]; j++)
	if (isPathBetter(hop_count, routingTable[destination][j].hop_count,
			 link_quality, routingTable[destination][j].link_quality)) {
	  found = TRUE;
	  break;
	}
	
      // if there is one, insert the new route above it
      if (found) {
	if (noOfRoutes[destination] < MAX_NUM_RECORDS)
	  noOfRoutes[destination]++;
	//else return; // Alterntive routes are already full

	// shift all routes from j... one position down 
	// (if there is no more space, the last will be overwritten)
	for (k = noOfRoutes[destination]-1; k < j; k--)
	  routingTable[destination][k] = routingTable[destination][k-1];

	// insert the new route into the j position
	routingTable[destination][j].node_id = destination;
	routingTable[destination][j].node_addr = destination_addr;
	routingTable[destination][j].hop_count = hop_count;
	routingTable[destination][j].link_quality = link_quality;
	routingTable[destination][j].nexthop = next_hop;
	routingTable[destination][j].timeout = MAX_TIMEOUT;
      }
      
      else {
	// insert new route into the last position if there is still space
	if (noOfRoutes[destination] < MAX_NUM_RECORDS) {
	  noOfRoutes[destination]++;
	  routingTable[destination][noOfRoutes[destination] - 1].node_id = destination;
	  routingTable[destination][noOfRoutes[destination] - 1].node_addr = destination_addr;
	  routingTable[destination][noOfRoutes[destination] - 1].hop_count = hop_count;
	  routingTable[destination][noOfRoutes[destination] - 1].link_quality = link_quality;
	  routingTable[destination][noOfRoutes[destination] - 1].nexthop = next_hop;
	  routingTable[destination][noOfRoutes[destination] - 1].timeout = MAX_TIMEOUT;	
	}
      }
    }
    //printRoutingTable(destination);  
    //sprintf(debugMsg, "[addNewPath()] ******** END\n");      
    //printDebugMessage(debugMsg);
  }

   /**
    * Test if one path is better than the other
    * First criteria: hop count
    * If hop counts are the same, test according to 
    * the link quality
    * 
    * @param new_hop_count The hop count of the new path
    * @param old_hop_count The hop count of the old path
    * @param new_link_quality The link quality of the new path
    * @param old_link_quality The link quality of the old path
    * 
    * @return Return if the new path is better than the old one
    */
  boolean isPathBetter(uint8_t new_hop_count, uint8_t old_hop_count, int8_t new_link_quality, int8_t old_link_quality) {
    
    if (new_hop_count < old_hop_count)
      return TRUE;
    else if /*(new_hop_count > old_hop_count)
      return FALSE;
    else if */(new_link_quality > old_link_quality)
      return TRUE;
/*
    if (new_link_quality < old_link_quality)
      return FALSE;*/
    else
      return FALSE;
  }
    

 /**
  * Removing an entry from the routing table
  * 
  * @param destination The destination for which a route should be removed
  * @param next_hop The next hop identifying the route that should be removed
  */
  void removeFromRoutingTable(uint8_t destination, uint8_t next_hop){
    uint8_t i, j;
    bool routeFound = FALSE;
    
    for (i = 0; i < noOfRoutes[destination]; i++)
      if (routingTable[destination][i].nexthop == next_hop) {
	routeFound = TRUE;
	//sprintf(debugMsg, "[removeFromRoutingTable()] For i=%u routeFound\n",i);      
	//printDebugMessage(debugMsg);
	break;
      }
      
    if (routeFound) {                        // remove route at index i
      for (j = i; j < noOfRoutes[destination] - 1; j++)
	routingTable[destination][i] = routingTable[destination][i + 1];
	noOfRoutes[destination]--;
      
      if (noOfRoutes[destination] == 0)
	// if there are no more routes to destination also remove all routes which have destination as their next hop
	for (i = 0; i < MAX_MOTES && i != destination; i++)
	  removeFromRoutingTable(i, destination);
      
      //sprintf(debugMsg, "[removeFromRoutingTable()] Neighbour=%u removed due to timeout\n",destination);      
      printDebugMessage(debugMsg);
      
      /// TODO transmit routing update at topology change
    }
  }

 /**
  * Choose next available path for sending a packet to a destination
  * 
  * @param destination The destination to which th packet should be sent
  * @param counter Identifies the alternative route to be used
  * 
  * @return true if there was an available path to choose, false otherwise
  */
  bool chooseNextAvailablePath(uint8_t destination, uint8_t counter) {
    
    if (noOfRoutes[destination] <= counter)
      return FALSE;
    
    // otherwise select the next hop at routingTable[destination][counter] and set task parameter accordingly
    sR_dest = routingTable[destination][counter].nexthop;  
    
    return TRUE;
  }

  /*******************/
  /* Debug functions */
  /*******************/


   /** 
    * Toggles a LED when a message is send to the radio. 
    */
  void radioBlink(){
//         call Leds.led0Toggle();
  }

   /** 
    * Toggles a LED when a message is send to the serial. 
    */
  void serialBlink(){
       // call Leds.led1Toggle();
  }

   /** 
    * Toggles a LED when a message couldn't be send and is dropped 
    */
  void failBlink(){
      //   call Leds.led2Toggle();
  }

  /**********/
  /* Events */
  /**********/

   /** 
    * When the device is booted, the radio and the serial device are initialized.
    * 
    * @see tos.interfaces.Boot.booted
    */
  event void Boot.booted(){
      uint8_t i,j;

      // Initialize the queues with the maximal values
      for(i = 0; i < MAX_MOTES; i++){
	  heads[i] = queues[i];
	  
	  for(j = 0; j < PACKET_QUEUE_SIZE; j++){
	      queues[i][j] = -1;
	  }
      }

      call RadioControl.start();
      call SerialControl.start();
  }

   /** 
    * Called, when the serial module was started.
    * 
    * @see tos.interfaces.SplitControl.startDone
    */
  event void SerialControl.startDone(error_t err){}
   /** 
    * Called, when the serial module was stopped.
    * 
    * @see tos.interfaces.SplitControl.stopDone
    */
  event void SerialControl.stopDone(error_t err){}
  
   /** 
    * Called, when message was sent over the serial device.
    * 
    * @see tos.interfaces.Send.sendDone
    */
  event void SerialSend.sendDone(message_t* m, error_t err){
      if(err == SUCCESS){
	  serialBlink();
      }else{
	  failBlink();
      }
  }
  

   /** 
    * This event is called, when a new message was received over the serial.
    * 
    * @see tos.interfaces.Receive.receive
    */
  event message_t* SerialReceive.receive(message_t* m, void* payload, uint8_t len){
      // Send an acknowledgement to the connected PC
      //post sendSerialAck();

      // Send the message over the radio to the specified destination
      
      forwardPacket(m,(myPacketHeader*)payload, len);
      return m;
  }

   /** 
    * Called, when the radio module was started.
    * Starts the routing timers and functionality
    * 
    * @see tos.interfaces.SplitControl.startDone
    */
  event void RadioControl.startDone(error_t err){
      initRouting();
  }
   /** 
    * Called, when the radio module was stopped.
    * 
    * @see tos.interfaces.SplitControl.stopDone
    */
  event void RadioControl.stopDone(error_t err){}


   /** 
    * Called, when the IP message was sent over the radio.
    * 
    * @see tos.interfaces.Send.sendDone
    */
  event void IPRadioSend.sendDone(message_t* m, error_t err) {	
      
    if (err == SUCCESS) {
      IPRadioBusy = FALSE;
      
      // if the packet was sent but not acknowledged, it will be resent using the next available path (maximum 2 times)
      if (!call PacketAcknowledgements.wasAcked(m) && retransmissionCounter < MAX_RETRANSMISSIONS) {
	retransmissionCounter++;
	if (chooseNextAvailablePath(sR_payload.destination, retransmissionCounter)) 
	  post sendRadio();
      }
	
//	radioBlink();
//	printf("IP Packet sent successfully from %u to %u \n",TOS_NODE_ID,sR_dest);
    }
    else 
      if (err == EBUSY)
	IPRadioBusy = TRUE;
      else
	failBlink();
  }

   /** 
    * Called, when the routing update message was sent over the radio.
    * 
    * @see tos.interfaces.Send.sendDone
    */
  event void RoutingRadioSend.sendDone(message_t* m, error_t err){	

    if (err == SUCCESS)
      routingRadioBusy = FALSE;
//	radioBlink();
//	printf("Routing update sent successfully from %u to %u \n",TOS_NODE_ID,sR_dest);
    else
      if (err == EBUSY)
	routingRadioBusy = TRUE;
      else
	failBlink();
  }

   /** 
    * This event is called, when a new IP message was received over the radio.
    * 
    * @see tos.interfaces.Receive.receive
    */
  event message_t* IPRadioReceive.receive(message_t* m, void* payload, uint8_t len){
      myPacketHeader *myph;
      am_addr_t source;

     // Discard if not a valid message
      if(call AMPacket.type(m) != AM_IP){
	return m;
      }

      // DEBUG
      call Leds.led1Toggle();
 
      myph = (myPacketHeader*) payload;
      source = myph->sender;

      //sprintf(debugMsg, "[IPRadioReceive] from source = %u \n",source);
      printDebugMessage(debugMsg);
      
      // Test, whether this message is a duplicate
      if (!inQueue(source, myph->seq_no, myph->ord_no)) {
	// Add this message to the queue of seen messages
	addToQueue(source, myph->seq_no, myph->ord_no); 
		
	// Test if the message is for us
	if (myph->destination == TOS_NODE_ID) {
	  // Forward it to the serial
	  sS_dest = AM_BROADCAST_ADDR; sS_m = *m; sS_len = len;
	  post sendSerial();
	}
	else {
	  // Forward it to the appropriate destination
	  forwardPacket(m, myph, len);
	}
      }
      return m;
  }
  
  /** 
  * This event is called, when a new routing update message was received over the radio.
  * 
  * @see tos.interfaces.Receive.receive
  */
  event message_t* RoutingRadioReceive.receive(message_t* m, void* payload, uint8_t len){
      routing_update_t* receivedRoutingUpdate;
      am_addr_t source;

      // Discard if not a valid message
      if (len != sizeof(routing_update_t)  || call AMPacket.type(m) != AM_ROUTING_UPDATE)
	return m;
      
//       //DEBUG
//       call Leds.led0Toggle();
      
      source = call AMPacket.source(m);
      
      //sprintf(debugMsg, "[RoutingRadioReceive.receive] from source=%u \n",source);
      printDebugMessage(debugMsg);
      
      receivedRoutingUpdate = (routing_update_t*) payload;
      processRoutingUpdate(receivedRoutingUpdate, source, call CC2420Packet.getRssi(payload));
      
      return m;
  }
  
 /**
  * Called when the timer for the routing updates expires.
  * When this timer is fired, the mote sends a distance vector version of its
  * routing table to its neighbors (node id and metric)
  * 
  * @see tos.interfaces.Timer.fired
  */
  event void TimerRoutingUpdate.fired() {
    sendRoutingUpdate();
  }
  
  /**
  * Called when the timer for updating the timeout of entries in the routing table expires.
  * When this timer is fired, the the timeout of each entry in the routing table is decreased by one
  * If zero is reached, the entry is removed
  * 
  * @see tos.interfaces.Timer.fired
  */
  event void TimerNeighborsAlive.fired() {

    uint8_t i, j;

    // for each route in the routing table evaluate the timeout values and remove dead routes
    for (i = 0; i < MAX_MOTES; i++) 
      for (j = 0; j < noOfRoutes[i]; j++) {
	routingTable[i][j].timeout--;

	// if the timeout becomes 0, remove the route from the routing table
	if (routingTable[i][j].timeout == 0)
	  removeFromRoutingTable(i, j);
      }
  }
  
  
  
      

}
