/**
 * @file   SimpleMoteAppP.nc
 * @author Marius Grysla, Oscar Dustman, Andrea Crotti
 * @date   Fri Aug 13 18:33:36 2010
 * 
 * @brief  Implementation of the MOTENET mote program.
 * 
 */


#include "SimpleMoteApp.h"

module SimpleMoteAppP{
    uses{
        // Standard interfaces
        interface Boot;
        interface Leds;

        // Radio interfaces
        interface SplitControl as RadioControl;
        // Send and receive interfaces for the IP packets
	interface AMSend as IPRadioSend;
        interface Receive as IPRadioReceive;
	// Send and receive interfaces for the beacon packets
	interface AMSend as BeaconRadioSend;
        interface Receive as BeaconRadioReceive;
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
	
	// Routing interfaces
	interface Timer<TMilli> as TimerBeacon;
	interface Timer<TMilli> as TimerRoutingUpdate;
	interface Timer<TMilli> as TimerNeighborsAlive;
    }
}
implementation{

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
    bool radioBusy = FALSE; 


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
	    break;
	  case AM_BEACON: 
	    if (!radioBusy) {
	      call BeaconRadioSend.send(sR_dest, &sR_m, sR_len);
	      radioBusy = TRUE;
// 	      call Leds.led1Toggle();
	    }
	    else
	      post sendRadio();
	    break;
	  case AM_ROUTING_UPDATE:
	    if (!radioBusy) {
	      call RoutingRadioSend.send(sR_dest, &sR_m, sR_len);
	      radioBusy = TRUE;
	      call Leds.led1Toggle();
	    }
	    else 
	      post sendRadio();
	    break;
	  default: call Leds.led2Toggle();
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
      radioBusy = FALSE;

      // start the timers for the beacon and for the routing updates
      call TimerBeacon.startPeriodic(2000);
      call TimerRoutingUpdate.startPeriodic(10000);
      
      // start timer for checking dead neighbors
//       call TimerNeighborsAlive.startPeriodic(1000);
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
    * Function for broadcasting a beacon
    */
    void sendBeacon() {
      beacons_t* beaconpkt = (beacons_t*)(call Packet.getPayload(&pkt, sizeof(beacons_t)));
  
      beaconpkt->node_id = TOS_NODE_ID;     // Node that created the packet			
      sR_type = AM_BEACON;
      // broadcast beacon over the radio
      sR_dest = AM_BROADCAST_ADDR; sR_m = pkt; sR_len = sizeof(beacons_t);
      post sendRadio();
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
	r_update_pkt->records[i].metric = routingTable[i].metric;
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
    void forwardPacket(message_t* msg, uint8_t len) {
      uint8_t i;
      am_addr_t nextHopAddress = AM_BROADCAST_ADDR;
      am_addr_t destination;
      bool found = FALSE;
      
      myPacketHeader* myph = (myPacketHeader*) msg;
      destination = myph->destination;
      
      for (i = 0; i < noOfRoutes; i++) {
	if (destination == routingTable[i].node_addr) {
	  nextHopAddress = routingTable[i].nexthop;
	  found = TRUE;
	  break;
	}
      }
      // If the the address was not found, use by default the broadcast.
      if (!found)
	return;

      // else forward it
      sR_type = AM_IP;
      sR_dest = nextHopAddress; sR_m = *msg; sR_len = len;
      post sendRadio();
    }


    /**
    * Process the information received in a beacon (add a new neighbor or confirm existing ones)
    * 
    * @param beaconMsg the beacon message received
    * @param sourceAddr the address if the node sending the beacon
    * 
    */
    void processBeacon(beacons_t* beaconMsg, am_addr_t sourceAddr) {
      bool isAlreadyNeighbor = FALSE;
      uint8_t i;
      
      for (i = 0; i < noOfRoutes; i++)
	if (routingTable[i].node_id == beaconMsg->node_id) {           // if a route already exists, reset the timeout
	  routingTable[i].timeout = MAX_TIMEOUT;
	  isAlreadyNeighbor = TRUE;
	  break;
	}
	
      if (!isAlreadyNeighbor && noOfRoutes < MAX_NUM_RECORDS) {        // else, add a new neighbor to the routing table
	noOfRoutes++;
	routingTable[noOfRoutes - 1].node_id = beaconMsg->node_id;
	routingTable[noOfRoutes - 1].node_addr = sourceAddr;
	routingTable[noOfRoutes - 1].metric = 1;
	routingTable[noOfRoutes - 1].nexthop = TOS_NODE_ID;
	routingTable[noOfRoutes - 1].timeout = MAX_TIMEOUT;
	
	// if changes in the topology have occurred, send updates
	sendRoutingUpdate();
      }
    }


    /**
    * Process the information received in a routing update
    * 
    * @param routingUpdateMsg the message with the routing updates
    * @param sourceAddr the address of the source nodes
    * 
    */
    void processRoutingUpdate(routing_update_t* routingUpdateMsg, am_addr_t sourceAddr) {

      uint8_t i, j;
      
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
	    if (updateRecords[i].node_id == TOS_NODE_ID || noOfRoutes >= MAX_NUM_RECORDS)
	      return;
	    
	    noOfRoutes++;
	    routingTable[noOfRoutes - 1].node_id = updateRecords[i].node_id;
	    routingTable[noOfRoutes - 1].node_addr = sourceAddr;
	    routingTable[noOfRoutes - 1].metric = updateRecords[i].metric + 1;
	    routingTable[noOfRoutes - 1].nexthop = senderNodeId;
	    routingTable[noOfRoutes - 1].timeout = MAX_TIMEOUT;
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
        call Leds.led1Toggle();
    }

    /** 
     * Toggles a LED when a message couldn't be send and is dropped 
     */
    void failBlink(){
//         call Leds.led2Toggle();
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
	forwardPacket(m, len);

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
        }else{
            failBlink();
        }
    }

    /** 
     * Called, when the beacon message was sent over the radio.
     * 
     * @see tos.interfaces.Send.sendDone
     */
    event void BeaconRadioSend.sendDone(message_t* m, error_t err){	
        radioBusy = FALSE;
	if(err == SUCCESS){
            radioBlink();
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
        radioBusy = FALSE;
	if(err == SUCCESS){
            radioBlink();
        }else{
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
	
	// discard if not a valid message
	if (len!= sizeof(myPacketHeader) || call AMPacket.type(m) != AM_IP)
	  return m;
	
	myph = (myPacketHeader*) payload;
	source = myph->sender;

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
	    forwardPacket(m, len);
	  }
	}
	
	return m;
    }
    

    /** 
     * This event is called, when a new beacon message was received over the radio.
     * 
     * @see tos.interfaces.Receive.receive
     */
    event message_t* BeaconRadioReceive.receive(message_t* m, void* payload, uint8_t len){

	beacons_t* receivedBeacon;
	am_addr_t source;
	
	// discard if not a valid message
	if (len != sizeof(beacons_t)  || call AMPacket.type(m) != AM_BEACON)
	  return m;
	
	source = call AMPacket.source(m);
	receivedBeacon = (beacons_t*) payload;
	processBeacon(receivedBeacon, source);
	
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

	// discard if not a valid message
	if (len != sizeof(routing_update_t)  || call AMPacket.type(m) != AM_ROUTING_UPDATE)
	  return m;
	
	source = call AMPacket.source(m);
	receivedRoutingUpdate = (routing_update_t*) payload;
	processRoutingUpdate(receivedRoutingUpdate, source);
	
	return m;
    }


    /**
    * Called when the timer for the beacon expires.
    * When this timer is fired, the mote broadcasts a beacon
    * 
    * @see tos.interfaces.Timer.fired
    */
    event void TimerBeacon.fired() {
      sendBeacon();
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
	  for (j = i; j < noOfRoutes - 1; j++)
	    routingTable[j] = routingTable[j + 1];
	  noOfRoutes--;
	}
      }
    }
}
