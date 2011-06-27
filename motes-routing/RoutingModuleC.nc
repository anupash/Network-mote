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
  // The main application
  components SimpleMoteAppC as App;
  
  // The routing module
  components new RoutingModuleP() as RoutingModuleP;
  
  // The radio components
  RoutingModuleP.RadioSend -> App;
  RoutingModuleP.Packet -> App;
  RoutingModuleP.AMPacket -> App;

  RoutingModuleP.RadioReceive -> App.Receive;
  

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

