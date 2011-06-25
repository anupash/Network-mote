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
  components RoutingModuleP as Routing;
  
  // The radio components
  components ActiveMessageC;
  Routing.RadioSend -> ActiveMessageC;
  Routing.RadioReceive -> ActiveMessageC.Receive;
  Routing.RadioPacket -> ActiveMessageC;
  Routing.RadioAMPacket -> ActiveMessageC;
//   Routing.PacketAcknowledgements -> ActiveMessageC;
  
  // The timer components
  components new TimerMilliC as TimerMilliBeacon;
  components new TimerMilliC as TimerMilliRoutingUpdate;
  components new TimerMilliC as TimerMilliNeighborsAlive;
  Routing.TimerBeacon -> TimerMilliBeacon;
  Routing.TimerRoutingUpdate -> TimerMilliRoutingUpdate; 
  Routing.TimerNeighborsAlive -> TimerMilliNeighborsAlive;
  
  // Standard components
  components LedsC;
  Routing.Leds -> LedsC;
}

