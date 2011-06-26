/**
 * @file RoutingModule.h
 * @author Anupam Ashish, Ignacio Martin Avellino Martinez, Oana Comanici
 * @date Thursday June 23, 2011
 *
 * @brief This file carries configuration variables and structs needed by the RoutingModule.
 *
 **/

#ifndef ROUTINGMODULE_H
#define ROUTINGMODULE_H

#include "AM.h"

/*
 * General definitions.
 */
enum {
  BEACON_TIMER_MILLI = 5120,
  MAX_NUM_RECORDS = 10,
  MAX_TIMEOUT = 15
};

/*
 * 
 */
enum {
  AM_ROUTING = 6
};

/* 
 * Types of messages for the routing module
 */
enum {
  AM_BEACON = 0x10,
  AM_ROUTING_UPDATE = 0x11
};


//typedef nx_uint8_t nx_boolean;
//typedef uint8_t boolean;


typedef nx_struct routing_record {
    nx_uint8_t node_id;
    nx_uint8_t metric;		
} routing_record_t;

typedef nx_struct routing_table {
    nx_uint8_t node_id;
    nx_am_addr_t node_addr;
    nx_uint8_t metric;
    nx_am_addr_t nexthop;
    nx_uint8_t timeout;
} routing_table_t;

typedef nx_struct routing_update {
    nx_uint8_t node_id;
    nx_uint8_t num_of_records;
    routing_record_t records[MAX_NUM_RECORDS];
} routing_update_t; 

typedef nx_struct beacons {
    nx_uint8_t node_id;
} beacons_t; 


typedef nx_struct ack {

} ack_t;

#endif
