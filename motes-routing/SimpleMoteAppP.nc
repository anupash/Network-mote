/**
 * @file   SimpleMoteAppP.nc
 * @author Marius Grysla, Oscar Dustman, Andrea Crotti, Anupam Ashish, Ignacio Avellino, Oana Comanici
 * @date   Fri Aug 13 18:33:36 2010
 * 
 * @brief  Implementation of the MOTENET mote program.
 * 
 */

#include "SimpleMoteApp.h"
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
  
  /*************************/
  /* Variables for routing */
  /*************************/
  
  // the routing table as an array of records
  routing_table_t routingTable[MAX_MOTES][MAX_NUM_RECORDS];
  uint8_t noOfRoutes[MAX_MOTES];

  message_t pkt;
  
  // whether radio is busy or available for transmission
  bool radioBusy; 

  /*************************/
  /* Function declarations */
  /*************************/

  void addNewPath(uint8_t destination, uint8_t next_hop, uint8_t hop_count, int8_t link_quality);
  void removeFromRoutingTable(uint8_t destination, uint8_t next_hop);
  bool isPathBetter(uint8_t new_hop_count, uint8_t old_hop_count, int8_t new_link_quality, int8_t old_link_quality);
  bool chooseNextAvailablePath(uint8_t destination);
  
  /*********/
  /* Tasks */
  /*********/

 /** 
  * A task for sending radio messages
  */
  task void sendRadio(){
      
    switch (sR_type) {
      
      case AM_IP: 
	if (!radioBusy) {
	  // request acknowledgement for the packet to be sent
          call PacketAcknowledgements.requestAck(&sR_m);
	  
	  if (call IPRadioSend.send(sR_dest, &sR_m, sR_len) == SUCCESS)
	    radioBusy = TRUE; 
	  else
	    post sendRadio();
	}
	else
	  post sendRadio();
	break;
      
      case AM_ROUTING_UPDATE:
	if (!radioBusy) {
	  if (call RoutingRadioSend.send(sR_dest, &sR_m, sR_len) == SUCCESS)
	    radioBusy = TRUE;
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
  * Initialize variables and timers of the routing module
  */
  void initRouting() {
    uint8_t i;
    
    // initialize routing table variables
    for (i = 0; i < MAX_MOTES; i++)
      noOfRoutes[i] = 0;
    radioBusy = FALSE;

    // start the timer for the routing updates
    call TimerRoutingUpdate.startPeriodic(5000);
    
    // start timer for checking dead neighbors
    call TimerNeighborsAlive.startPeriodic(1000);
  }
  
 /** 
  * Test, whether a message signature is in the queue (was recently seen).
  * 
  * @param client The TOS_NODE_ID. Should be smaller that MAX_MOTES!!!
  * @param seq_no The sequential number of the message.
  * @param ord_no The chunk number.
  * 
  * @return TRUE, if the signature is contained, FALSE otherwise.
  */
  bool inQueue(am_addr_t client, seq_no_t seq_no, uint8_t ord_no){
      uint8_t i;
      uint16_t identifier;

      // Build identifier from seq_nr and ord_nr
      identifier = (((uint16_t) seq_no) << 8) | ord_no;

      // Position 0 of the queue reserved for the Gateway
      // This is done because the size of queue is limited to MAX_MOTES
      if (client == 254) client = 0;
      
      // Just loop over all elements
      for(i = 0; i < PACKET_QUEUE_SIZE; i++){
	  if(queues[client][i] == identifier){
	      return TRUE;
	  }
      }
      
      return FALSE;
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

      // Position 0 of the queue reserved for the Gateway
      // This is done because the size of queue limited to MAX_MOTES
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
  * It only sends existing routes from the routing table (not MAX_MOTES extries)
  */
  void sendRoutingUpdate() {
    uint8_t i;
    uint8_t noOfRoutesUpdate = 0;
    routing_update_t* r_update_pkt = (routing_update_t*)(call Packet.getPayload(&pkt, sizeof(routing_update_t)));
    
    r_update_pkt->node_id = TOS_NODE_ID;
    
    // add best routes from the routing table
    for (i = 0; i < MAX_MOTES; i++) {
      if (noOfRoutes[i] > 0) {
	r_update_pkt->records[noOfRoutesUpdate].node_id = i;
	r_update_pkt->records[noOfRoutesUpdate].hop_count = routingTable[i][0].hop_count;
	r_update_pkt->records[noOfRoutesUpdate].link_quality = routingTable[i][0].link_quality;
	noOfRoutesUpdate++;
      }
    }

    r_update_pkt->num_of_records = noOfRoutesUpdate;			

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
    uint8_t myDestination;

    // If this mote is a node attached to a PC, set the correct destination.
    if (TOS_NODE_ID == 1) 
      myph->destination = 254;
    else 
      if (TOS_NODE_ID == 254) 
	myph->destination = 1;
    
    // destination for looking up in the routing table
    myDestination = myph->destination == 254 ? 0 : myph->destination;
    
    // resolve next hop for destination (take into account the conversion from routing table to normal representation for gateway)
    if (noOfRoutes[myDestination] > 0)
      nextHopAddress = routingTable[myDestination][0].next_hop == 0 ? 254 : routingTable[myDestination][0].next_hop;
    
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
  * @param routingUpdateMsg the message with the routing updates (only payload)
  * @param linkQuality the quality of the link between the sending node and this node
  * 
  */
  void processRoutingUpdate(routing_update_t* routingUpdateMsg, int8_t linkQuality) {

    uint8_t myID;
    bool ignore = FALSE;
    uint8_t i;
    
    uint8_t senderNodeID = routingUpdateMsg->node_id;
    uint8_t noOfRoutesUpdate = routingUpdateMsg->num_of_records;
    routing_record_t* updateRecords = routingUpdateMsg->records;
    

    // set the node IDs in the routing table convention - gateway is 0
    myID = TOS_NODE_ID == 254 ? 0 : TOS_NODE_ID;
    senderNodeID = senderNodeID == 254 ? 0 : senderNodeID;

    ignore =  (TOS_NODE_ID == 1 && senderNodeID == 0) ||
// 	      (TOS_NODE_ID == 1 && senderNodeID == 3) ||
	      (TOS_NODE_ID == 2 && senderNodeID == 3) ||
	      (TOS_NODE_ID == 3 && senderNodeID == 2) ||
	      (TOS_NODE_ID == 254 && senderNodeID == 1)
// 	      (TOS_NODE_ID == 254 && senderNodeID == 2);
	      ;
    
    if (ignore)
      return;

    blinkRoutingRadioReceive();
    
    // add the sending node as a neighbor
    addNewPath(senderNodeID, senderNodeID, 1, linkQuality);
    
    // then process the routing update records one by one
    for (i = 0; i < noOfRoutesUpdate; i++)
      if (updateRecords[i].node_id != myID)
	addNewPath(updateRecords[i].node_id, senderNodeID, updateRecords[i].hop_count + 1, (updateRecords[i].link_quality + linkQuality) / (updateRecords[i].hop_count + 1));
  }
    

 /**
  * Add a new path to a certain destination in the routingTable
  * 
  * @param destination The destination for which a new path should be added 
  * @param next_hop The next hop in the new path
  * @param hop_count The new hop count to destination
  * @param link_quality The new link quality of the path
  */
  void addNewPath(uint8_t destination, uint8_t next_hop, uint8_t hop_count, int8_t link_quality) {
    uint8_t i, j, k;
    routing_table_t aux;
    bool worstFound = FALSE;
    bool routeFound = FALSE;
    
    // first check if the new path already exists
    for (i = 0; i < noOfRoutes[destination]; i++) {
      
      if (routingTable[destination][i].next_hop == next_hop) {
      
	// if the exact same path and metric already exists, do nothing
	if (routingTable[destination][i].hop_count == hop_count &&
	    routingTable[destination][i].link_quality == link_quality){
	  routingTable[destination][i].timeout = MAX_TIMEOUT;
	  return;
	}
	// else if the metric has changed 
	// check if the new metric is acceptable (link quality is above a certain threshold)
	// otherwise remove the route from the routing table and send a routing update to announce the topology has changed
	if (link_quality < MIN_LINK_QUALITY) {
	  removeFromRoutingTable(destination, next_hop);
	  sendRoutingUpdate();
	  return;
	}
	
	routeFound = TRUE;
	break;                     // same route is found but with different metric, stop searching further
      }
    }
    
    if (routeFound) {
      
      // update the existing metric and re-order the paths
      routingTable[destination][i].hop_count = hop_count;
      routingTable[destination][i].link_quality = link_quality;
      routingTable[destination][i].timeout = MAX_TIMEOUT;
      
      // find the first path (j) with a worse metric than this (i) 
      worstFound = FALSE;
      for (j = 0; j < noOfRoutes[destination]; j++) {
	if (j != i && isPathBetter(routingTable[destination][i].hop_count, routingTable[destination][j].hop_count,
				  routingTable[destination][i].link_quality, routingTable[destination][j].link_quality)) {
	  worstFound = TRUE;
	  break;
	}
      }
      
      if (worstFound) {
	// re-order the paths according to metric
	aux = routingTable[destination][i];
      
	// if the route must be promoted
	if (j < i) {
	  // move j...i-1 to the right
	  for (k = i; k > j; k--)
	    routingTable[destination][k] = routingTable[destination][k - 1];
	  
	  // insert i in j
	  routingTable[destination][j] = aux;
	}
	else {  // if the route must be degraded
	  // move i+1...j-1 to the left
	  for (k = i + 1; k < j; k++)
	    routingTable[destination][k - 1] = routingTable[destination][k];
	  // insert i in j-1
	  routingTable[destination][j - 1] = aux;
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
      
      // check if the link quality is acceptable
      if (link_quality < MIN_LINK_QUALITY)
	return;

      // find the first path (j) with a worse metric than the new one 
      worstFound = FALSE;
      for (j = 0; j < noOfRoutes[destination]; j++)
	if (isPathBetter(hop_count, routingTable[destination][j].hop_count,
			 link_quality, routingTable[destination][j].link_quality)) {
	  worstFound = TRUE;
	  break;
	}
	
      // if there is one, insert the new route above it
      if (worstFound) {
	if (noOfRoutes[destination] < MAX_NUM_RECORDS)
	  noOfRoutes[destination]++;

	// shift all routes from j... one position down 
	// (if there is no more space, the last will be overwritten)
	for (k = noOfRoutes[destination] - 1; k > j; k--)
	  routingTable[destination][k] = routingTable[destination][k - 1];

	// insert the new route into the j position
	routingTable[destination][j].next_hop = next_hop;
	routingTable[destination][j].hop_count = hop_count;
	routingTable[destination][j].link_quality = link_quality;
	routingTable[destination][j].timeout = MAX_TIMEOUT;
      }
      
      else {
	// insert new route into the last position if there is still space
	if (noOfRoutes[destination] < MAX_NUM_RECORDS) {
	  noOfRoutes[destination]++;	
	  routingTable[destination][noOfRoutes[destination] - 1].next_hop = next_hop;
	  routingTable[destination][noOfRoutes[destination] - 1].hop_count = hop_count;
	  routingTable[destination][noOfRoutes[destination] - 1].link_quality = link_quality;
	  routingTable[destination][noOfRoutes[destination] - 1].timeout = MAX_TIMEOUT;	
	}
      }
    }
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
  * @return Return TRUE if the new path is better than the old one, FALSE else
  */
  bool isPathBetter(uint8_t new_hop_count, uint8_t old_hop_count, int8_t new_link_quality, int8_t old_link_quality) {
    
    if (new_hop_count < old_hop_count)
      return TRUE;
    else if (new_hop_count > old_hop_count)
      return FALSE;
    else if (new_link_quality > old_link_quality)
      return TRUE;

    return FALSE;
  }
    

 /**
  * Remove an entry from the routing table
  * 
  * @param destination The destination for which a route should be removed
  * @param next_hop The next hop identifying the route that should be removed
  * 
  */
  void removeFromRoutingTable(uint8_t destination, uint8_t next_hop){
    uint8_t i, j;
    bool routeFound = FALSE;
    
    for (i = 0; i < noOfRoutes[destination]; i++)
      if (routingTable[destination][i].next_hop == next_hop) {
	routeFound = TRUE;
	break;
      }
      
    if (routeFound) {                        // remove route at index i
      for (j = i; j < noOfRoutes[destination] - 1; j++)
	routingTable[destination][j] = routingTable[destination][j + 1];
	noOfRoutes[destination]--;
      
      if (noOfRoutes[destination] == 0)
	// if there are no more routes to destination also remove all routes which have destination as their next hop
	for (i = 0; i < MAX_MOTES; i++)
	  removeFromRoutingTable(i, destination);
    }
  }

 /**
  * Choose next available path for sending a packet to a destination
  * 
  * @param destination The destination to which the packet should be sent
  * 
  * @return TRUE if there was an available path to choose, FALSE otherwise
  */
  bool chooseNextAvailablePath(uint8_t destination) {
    
    // convert destination to routing table format
    destination = (destination == 254) ? 0 : destination;
    
    // delete current best route and send a new routing update with the topology changes
    removeFromRoutingTable(destination, routingTable[destination][0].next_hop);

    // set task parameter according to the new next hop
    if (noOfRoutes[destination] <= 0)
      return FALSE;
    sR_dest = routingTable[destination][0].next_hop;  
    
    return TRUE;
  }

  /*******************/
  /* Debug functions */
  /*******************/

 /** 
  * Toggles a LED when a message is sent through the radio. 
  */
  void blinkIPRadioSent(){
    call Leds.led0Toggle();
  }

 /** 
  * Toggles a LED when a message is received through the radio 
  */
  void blinkIPRadioReceived(){
    call Leds.led1Toggle();
  }

 /** 
  * Toggles a LED when a routing update was received
  */
  void blinkRoutingRadioReceive(){
    call Leds.led2Toggle();
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
/*    if (err == SUCCESS)
      serialBlink();
    else
      failBlink();*/
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
      forwardPacket(m, (myPacketHeader*) payload, len);
      return m;
  }

 /** 
  * Called when the radio module was started.
  * Starts the routing timers and functionality
  * 
  * @see tos.interfaces.SplitControl.startDone
  */
  event void RadioControl.startDone(error_t err) {
    initRouting();
  }

 /** 
  * Called when the radio module was stopped.
  * 
  * @see tos.interfaces.SplitControl.stopDone
  */
  event void RadioControl.stopDone(error_t err) {}

 /** 
  * Called when the IP message was sent over the radio.
  * 
  * @see tos.interfaces.Send.sendDone
  */
  event void IPRadioSend.sendDone(message_t* m, error_t err) {	
      
    if (err == SUCCESS) {
      radioBusy = FALSE;
      
      blinkIPRadioSent();
      
      // if the packet was sent but not acknowledged, it will be resent using the next available path (maximum 3 times)
      if (!call PacketAcknowledgements.wasAcked(m) && retransmissionCounter < MAX_RETRANSMISSIONS) {
	retransmissionCounter++;
	if (chooseNextAvailablePath(sR_payload.destination)) 
	  post sendRadio();
      }
    }

    else 
      if (err == EBUSY)
	radioBusy = TRUE;
//       else
// 	failBlink();
  }

 /** 
  * Called when the routing update message was sent over the radio.
  * 
  * @see tos.interfaces.Send.sendDone
  */
  event void RoutingRadioSend.sendDone(message_t* m, error_t err){	

    if (err == SUCCESS)
      radioBusy = FALSE;
    else
      if (err == EBUSY)
	radioBusy = TRUE;
//       else
// 	failBlink();
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
    if (call AMPacket.type(m) != AM_IP)
      return m;

    blinkIPRadioReceived();
    
    myph = (myPacketHeader*) payload;
    source = myph->sender;

    // Test whether this message is a duplicate
    if (!inQueue(source, myph->seq_no, myph->ord_no)) {
      // Add this message to the queue of seen messages
      addToQueue(source, myph->seq_no, myph->ord_no); 
	      
      // Test if the message is for us
      if (myph->destination == TOS_NODE_ID) {
	// Forward it to the serial
	sS_dest = AM_BROADCAST_ADDR; 
	sS_m = *m; 
	sS_len = len;
	post sendSerial();
      }
      else
	// Forward it to the appropriate destination
	forwardPacket(m, myph, len);
    }
    return m;
  }
  
 /** 
  * This event is called when a new routing update message was received over the radio.
  * 
  * @see tos.interfaces.Receive.receive
  */
  event message_t* RoutingRadioReceive.receive(message_t* m, void* payload, uint8_t len) {
    routing_update_t* receivedRoutingUpdate;

    // Discard if not a valid message
    if (call AMPacket.type(m) != AM_ROUTING_UPDATE)
      return m;
    
    receivedRoutingUpdate = (routing_update_t*) payload;
    processRoutingUpdate(receivedRoutingUpdate, call CC2420Packet.getRssi(payload));
    
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
    bool topologyChanged = FALSE;

    // for each route in the routing table evaluate the timeout values and remove dead routes
    for (i = 0; i < MAX_MOTES; i++) 
      for (j = 0; j < noOfRoutes[i]; j++) {
	routingTable[i][j].timeout--;

	// if the timeout becomes 0, remove the route from the routing table
	if (routingTable[i][j].timeout == 0) {
	  removeFromRoutingTable(i, routingTable[i][j].next_hop);
	  topologyChanged = TRUE;
	}
      }
      
     // send a routing update if the topology has changed
     if (topologyChanged)
       sendRoutingUpdate();
  }

}
