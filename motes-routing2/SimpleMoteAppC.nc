/**
 * @file   SimpleMoteAppC.nc
 * @author Marius Grysla, Oscar Dustman, Andrea Crotti
 * @date   Fri Aug 13 18:31:27 2010
 * 
 * @brief  The configuration file for the MOTENET mote program.
 *
 * SimpleMoteApp broadcasts packets it gets from the serial port to the network.
 * Every mote has a list of recently seen packets that assures, that no duplicates are 
 * broadcasted.
 * If a packet has the current node as destination it is forwarded to the PC/Gateway.
 * 
 */

#include "SimpleMoteApp.h"

configuration SimpleMoteAppC{
}
implementation{
    // The Program
    components SimpleMoteAppP;

    // Standard components
    components MainC, LedsC;
    SimpleMoteAppP.Boot -> MainC;
    SimpleMoteAppP.Leds -> LedsC;

    // Radio components - IP packets
    components ActiveMessageC as Radio;
    components new SendQueueC(RADIO_QUEUE_SIZE, sizeof(message_t)) as IPRadioQueue;
    IPRadioQueue.LowSend -> Radio.AMSend[AM_IP];
    IPRadioQueue.AMPacket -> Radio;
    IPRadioQueue.Packet -> Radio;

    // Radio components - Beacon packets
    components new SendQueueC(RADIO_QUEUE_SIZE, sizeof(message_t)) as BeaconRadioQueue;
    BeaconRadioQueue.LowSend -> Radio.AMSend[AM_BEACON];
    BeaconRadioQueue.AMPacket -> Radio;
    BeaconRadioQueue.Packet -> Radio;

    // Radio components - IP packets
    components new SendQueueC(RADIO_QUEUE_SIZE, sizeof(message_t)) as RoutingRadioQueue;
    RoutingRadioQueue.LowSend -> Radio.AMSend[AM_ROUTING_UPDATE];
    RoutingRadioQueue.AMPacket -> Radio;
    RoutingRadioQueue.Packet -> Radio;
    
    SimpleMoteAppP.RadioControl -> Radio;
    
    SimpleMoteAppP.IPRadioReceive -> Radio.Receive[AM_IP];
    SimpleMoteAppP.IPRadioSend -> IPRadioQueue;
    
    SimpleMoteAppP.BeaconRadioReceive -> Radio.Receive[AM_BEACON];
    SimpleMoteAppP.BeaconRadioSend -> BeaconRadioQueue;

    SimpleMoteAppP.RoutingRadioReceive -> Radio.Receive[AM_ROUTING_UPDATE];
    SimpleMoteAppP.RoutingRadioSend -> RoutingRadioQueue;

    // Serial components
    components SerialActiveMessageC as Serial;
    components new SendQueueC(SERIAL_QUEUE_SIZE, sizeof(message_t)) as SerialQueue;
    SerialQueue.LowSend -> Serial.AMSend[AM_SIMPLE_SERIAL];
    SerialQueue.AMPacket -> Serial;
    SerialQueue.Packet -> Serial;

    SimpleMoteAppP.SerialControl -> Serial;
    SimpleMoteAppP.SerialReceive -> Serial.Receive[AM_SIMPLE_SERIAL];
    SimpleMoteAppP.SerialSend -> SerialQueue;

    // Packet interfaces
    SimpleMoteAppP.Packet -> Radio;
    SimpleMoteAppP.AMPacket -> Radio;
    
    // The timer components
    components new TimerMilliC() as TimerMilliBeacon;
    components new TimerMilliC() as TimerMilliRoutingUpdate;
    components new TimerMilliC() as TimerMilliNeighborsAlive;
    SimpleMoteAppP.TimerBeacon -> TimerMilliBeacon;
    SimpleMoteAppP.TimerRoutingUpdate -> TimerMilliRoutingUpdate; 
    SimpleMoteAppP.TimerNeighborsAlive -> TimerMilliNeighborsAlive;
    
}
