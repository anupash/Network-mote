/**
 * @file   SimpleMoteAppP.nc
 * @author Marius Grysla, Oscar Dustman, Andrea Crotti
 * @date   Fri Aug 13 18:33:36 2010
 * 
 * @brief  Implementation of the MOTENET mote program.
 * 
 */

#include "SimpleMoteApp.h"
//#include "printf.h"

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
  uint8_t sR_len;
  uint16_t sR_type;
  
  // Variables used for serial sending task
  am_addr_t sS_dest;
  message_t sS_m;
  uint8_t sS_len;
  
  /*************************/
  /* Variables for routing */
  /*************************/
  
  // the routing table as an array of records
  routing_table_t routingTable[MAX_NUM_RECORDS];
  uint8_t noOfNeighbours;

  // the number of records of the routing table
  uint8_t noOfRoutes;
  message_t pkt;
  
  // whether radio is busy or available for transmission
  bool routingRadioBusy; 


  /*********/
  /* Tasks */
  /*********/

  /** 
  * A task for sending radio messages
  */
  task void sendRadio(){
      switch (sR_type) {
	
	case AM_IP: 
	  call IPRadioSend.send(sR_dest, &sR_m, sR_len);
// 	  //DEBUG
	  call Leds.led1Toggle();
//	    printf("[sendRadio] AM_IP sent from %u = to %u = \n",TOS_NODE_ID,sR_dest);
	  break;
	
	case AM_ROUTING_UPDATE:
	  if (!routingRadioBusy) {
	    if (call RoutingRadioSend.send(sR_dest, &sR_m, sR_len) == SUCCESS){
	      routingRadioBusy = TRUE;
//		printf("[sendRadio] AM_ROUTING_UPDATE sent from %u = to %u = \n",TOS_NODE_ID,sR_dest);
	    }
	    else {
	      routingRadioBusy = FALSE;
	      post sendRadio();
	    }
	  }
	  else {
	    post sendRadio();
	  }
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
    
    // initialize routing table variables
    noOfRoutes = 0;
    routingRadioBusy = FALSE;

    // start the timer for the routing updates
    call TimerRoutingUpdate.startPeriodic(5000);
    
    // start timer for checking dead neighbors
    call TimerNeighborsAlive.startPeriodic(1000);
//    printfflush();
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
  * Functions for sending the routing updates to the neighbors
  */
  void sendRoutingUpdate() {
    uint8_t i;
    routing_update_t* r_update_pkt = (routing_update_t*)(call Packet.getPayload(&pkt, sizeof(routing_update_t)));
    
    r_update_pkt->node_id = TOS_NODE_ID;
    r_update_pkt->num_of_records = noOfRoutes;			
    
    // routes from the routing table
    for (i = 0; i < noOfRoutes; i++) {
      r_update_pkt->records[i].node_id = routingTable[i].node_id;
      r_update_pkt->records[i].hop_count = routingTable[i].hop_count;
      r_update_pkt->records[i].link_quality = routingTable[i].link_quality;
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
  * If it is not found, the broadcast address is used.
  * 
  * @param msg the message to be sent
  * @param len the length of the message to be sent
  * 
  */
  void forwardPacket(message_t* msg, myPacketHeader* myph, uint8_t len) {
    uint8_t i;
    am_addr_t nextHopAddress;// = AM_BROADCAST_ADDR;
    bool found = FALSE;
//    myPacketHeader* myph = (myPacketHeader*) msg;

    // If this mote is a node attatched to a PC, set the correct destination.
    if(TOS_NODE_ID == 1) myph->destination = 254;
    else if (TOS_NODE_ID == 254 ) myph->destination = 1;
    
//    printf("[forwardPacket] At node= %u destination received = %u ",TOS_NODE_ID,myph->destination); 
    for (i = 0; i < noOfRoutes; i++) {
      if (myph->destination == routingTable[i].node_id) {
		nextHopAddress = routingTable[i].nexthop;
		found = TRUE;
		break;
      }
    }
  
    if (!found) {       // If the the address was not found, drop it
      
    }
    else {     // else forward it
      sR_type = AM_IP;
      sR_dest = nextHopAddress; sR_m = *msg; sR_len = len;
      post sendRadio();
    }
  }

 /**
  * Process the information received in a routing update
  * 
  * @param routingUpdateMsg the message with the routing updates
  * @param sourceAddr the address of the source nodes
  * 
  */
  void processRoutingUpdate(routing_update_t* routingUpdateMsg, am_addr_t sourceAddr, int8_t linkQuality) {

    uint8_t i, j;
    int idx;
    bool isNeighbor = FALSE;
    
    uint8_t senderNodeId = routingUpdateMsg->node_id;
    uint8_t noOfRoutesUpdate = routingUpdateMsg->num_of_records;
    routing_record_t* updateRecords = routingUpdateMsg->records;
    
//      printf("inside [processRoutingUpdate] current noOfRoutes = %u \n",noOfRoutes); 

    // check if the source is already in the routing table
    for (i = 0; i < noOfRoutes; i++) {
      // if it has a route to it, make hop_count 1 (make it a neighbor)
      if (routingTable[i].node_id == senderNodeId) {
	routingTable[i].hop_count = 1;
	routingTable[i].link_quality = linkQuality;
	routingTable[i].nexthop = senderNodeId;
	routingTable[i].timeout = MAX_TIMEOUT;
	isNeighbor = TRUE;
	break;
      }
    }
    
    // if it is not a neighbor already, add it with hop_count 1
    if (!isNeighbor && noOfRoutes < MAX_NUM_RECORDS) {
      noOfRoutes++;
      routingTable[noOfRoutes - 1].node_id = senderNodeId;
      routingTable[noOfRoutes - 1].node_addr = sourceAddr;
      routingTable[noOfRoutes - 1].hop_count = 1;
      routingTable[noOfRoutes - 1].link_quality = linkQuality;
      routingTable[noOfRoutes - 1].nexthop = senderNodeId;
      routingTable[noOfRoutes - 1].timeout = MAX_TIMEOUT;
//        printf("[processRoutingUpdate] New Neighbour senderNodeID = %u and sourceAddr = %u noOfRoutes = %u \n ",senderNodeId, sourceAddr,noOfRoutes);
    }
    
    // For each entry in the routing update received, check if this entry exists in the routing table and update it or create it
    for (i = 0; i < noOfRoutesUpdate; i++) {
      idx = -1;
      for (j = 0; j < noOfRoutes; j++) {                       
	// If there is an entry, check if the new route is better and update the next hop, hop count & link quality
	if (routingTable[j].node_id == updateRecords[i].node_id)
	  idx = j;
      }
      
      if(idx == -1) {
	//if not found in my routing table and i am not the neighbour of the sender
	//important because the sender would have been already added to the routing table
	if(updateRecords[i].node_id != TOS_NODE_ID) {
	  noOfRoutes++;
	  routingTable[noOfRoutes - 1].node_id = updateRecords[i].node_id;
	  routingTable[noOfRoutes - 1].node_addr = sourceAddr;
	  routingTable[noOfRoutes - 1].hop_count = updateRecords[i].hop_count + 1;
	  routingTable[noOfRoutes - 1].link_quality = (updateRecords[i].link_quality + linkQuality) / (updateRecords[i].hop_count + 1);
	  routingTable[noOfRoutes - 1].nexthop = senderNodeId;
	  routingTable[noOfRoutes - 1].timeout = MAX_TIMEOUT;
//            printf("[processRoutingUpdate] when idx = -1 added node_id = %u TOS_NODE_ID = %u \n",updateRecords[i].node_id,TOS_NODE_ID);
	}
      }
      else {
	if(noOfRoutes >= MAX_NUM_RECORDS) {
	  return;
	}
	else
	{

	//[not important can be removed] but check again before removing
	//case where sender is the neighbour 
	  if ((updateRecords[i].node_id == TOS_NODE_ID) && (routingTable[idx].node_id == senderNodeId)) {
	      routingTable[idx].hop_count = 1;
	      routingTable[idx].link_quality = linkQuality;
	      routingTable[idx].nexthop = senderNodeId;
	      routingTable[idx].timeout = MAX_TIMEOUT;
	      return;
	  }
	  else if (routingTable[idx].link_quality < (updateRecords[i].link_quality + linkQuality) / (updateRecords[i].hop_count + 1)) {
//          printf("[processRoutingUpdate] New Route has better link sender = %u source = %u oldlink_q = %d newlink_q = %d \n",senderNodeId, sourceAddr, routingTable[idx].link_quality,
//										(updateRecords[i].link_quality + linkQuality) / (updateRecords[i].hop_count + 1) );
	      routingTable[idx].link_quality = (updateRecords[i].link_quality + linkQuality) / (updateRecords[i].hop_count + 1);
	      routingTable[idx].nexthop = senderNodeId;
	      routingTable[idx].timeout = MAX_TIMEOUT;   // added because timeout timer has to be reset everytime a new update comes
		}
	    else if (routingTable[idx].hop_count > updateRecords[i].hop_count + 1) { 
//          printf("[processRoutingUpdate] New Route has better link sender = %u source = %u oldhopcount = %d newhopcount = %d \n",senderNodeId, sourceAddr,routingTable[idx].hop_count ,
//										(updateRecords[i].hop_count+1) );
			routingTable[idx].nexthop = senderNodeId;
			routingTable[idx].hop_count = updateRecords[i].hop_count + 1;
			routingTable[idx].timeout = MAX_TIMEOUT;   // added because timeout timer has to be reset everytime a new update comes
//            printf("[processRoutingUpdate] New Route has better hop count  in [IF] sender = %u source = %u \n",senderNodeId, sourceAddr);
	    }else{ /*case when the node is in the routingTable but it is not a neighbor we need to update the timeout*/
//          printf("[processRoutingUpdate] Just update the Timeout for node = %u as it already exists in the routingTable \n",routingTable[idx].node_id);
	      routingTable[idx].timeout = MAX_TIMEOUT;
		}
	  
	}
      }
    }
  }

  /*******************/
  /* Debug functions */
  /*******************/


   /** 
    * Toggles a LED when a message is send to the radio. 
    */
  void radioBlink(){
         call Leds.led0Toggle();
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
  event void IPRadioSend.sendDone(message_t* m, error_t err){	
      if(err == SUCCESS){
	radioBlink();
//	printf("IP Packet sent successfully from %u to %u \n",TOS_NODE_ID,sR_dest);
      }else{
	failBlink();
      }
  }

   /** 
    * Called, when the routing update message was sent over the radio.
    * 
    * @see tos.interfaces.Send.sendDone
    */
  event void RoutingRadioSend.sendDone(message_t* m, error_t err){	
      routingRadioBusy = FALSE;
      if(err == SUCCESS){
	radioBlink();
//	printf("Routing update sent successfully from %u to %u \n",TOS_NODE_ID,sR_dest);
      } else {
	failBlink();
      }
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

//	printf("[IPRadioReceive] from source = %u \n",source);
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
      
      //DEBUG
      call Leds.led2Toggle();
      
      source = call AMPacket.source(m);
//	printf("[RoutingRadioReceive.receive] from source=%u \n",source);
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
    
    for (i = 0; i < noOfRoutes; i++) {
      routingTable[i].timeout--;
      // if the timeout becomes 0, remove the route from the routing table
      if (routingTable[i].timeout == 0) {
//		 printf("[TimerNeighborsAlive.fired()] Neighbour=%u removed due to timeout\n",routingTable[i].node_id);

	for (j = i; j < noOfRoutes - 1; j++) {
	  routingTable[j] = routingTable[j + 1];
	}
	noOfRoutes--;
		if(noOfRoutes <= 0 ) break;
      }
    }
  }
}
