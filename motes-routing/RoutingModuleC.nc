/**
 * @file   RoutingModuleC.nc
 * @author Oana Comanici, Ignacio Avellino, Anupam Ashish
 * 
 * @brief  Configuration file for the Routing module.
 * 
 * This file wires the RoutingModule and creates the needed components.
 */


generic configuration RoutingModuleC() @safe() {
  provides interface Routing;
}

implementation {
  // The routing module
  components new RoutingModuleP() as RoutingModuleP;
  
  // The radio components
  components ActiveMessageC;
  components new AMSenderC(AM_ROUTING);
  components new AMReceiverC(AM_ROUTING);
  
  RoutingModuleP.RadioControl -> ActiveMessageC;
  
  RoutingModuleP.RadioSend -> AMSenderC;
  RoutingModuleP.Packet -> AMSenderC;
  RoutingModuleP.AMPacket -> AMSenderC;

  RoutingModuleP.RadioReceive -> ActiveMessageC.Receive;
  

//   RoutingModuleP.PacketAcknowledgements -> ActiveMessageC;
  
  // The timer components
  components new TimerMilliC() as TimerMilliBeacon;
  components new TimerMilliC() as TimerMilliRoutingUpdate;
  components new TimerMilliC() as TimerMilliNeighborsAlive;
  RoutingModuleP.TimerBeacon -> TimerMilliBeacon;
  RoutingModuleP.TimerRoutingUpdate -> TimerMilliRoutingUpdate; 
  RoutingModuleP.TimerNeighborsAlive -> TimerMilliNeighborsAlive;
  
  // Standard components
  components LedsC;
  RoutingModuleP.Leds -> LedsC;
}

