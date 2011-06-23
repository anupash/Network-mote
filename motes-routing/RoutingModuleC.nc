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
  
  uses {}
}

implementation {
  // The routing module
  components RoutingModuleP as Routing;
  
  // The radio component
  components ActiveMessageC;
  
  // The timer components
  components new TimerMilliC as TimerMilliBeacon;
  components new TimerMilliC as TimerMilliNeighborsAlive;
  
  components LedsC;
}

