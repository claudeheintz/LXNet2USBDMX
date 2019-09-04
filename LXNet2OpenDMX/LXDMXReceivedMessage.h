//
//  LXDMXReceivedMessage.h
//  LXDMX
//
//  Created by Claude Heintz on 9/27/10.
//  Copyright 2010-2016 Claude Heintz Design. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include "LXDMXCommonInclude.h"

/*
 * LXDMXReceivedMessage encapsulates DMX data including up to a universe of slots aka dimmers/channels/addresses,
 * the number of slots aka dimmers/channels/addresses (length)
 * and the universe, which is a zero based index where dimmer/address = 1 + slot/index + 512*universe
 *
 * LXDMXReceivedMessage is designed for a buffering arrangement where DMX data can be received on one thread
 * and processed on another.  By handing off the received data to a LXDMXReceivedMessage object,
 * the receiving thread is free to continue to read additional packets.
 */

@interface LXDMXReceivedMessage : NSObject {
    /*
     *  _slotsLength is the number of dmx levels aka dimmers/addresses/slots
     */
    int _slotsLength;
    /*
     *  _universeindex is the universe number (zero based)
     */
    int _universeindex;
    /*
     *  _slotsData is the array of DMX levels
     */
    unsigned char _slotsData[DMX_DIMMERS_IN_UNIVERSE];
    /*
     *  _unread flag to mark if the data from this message has been read by a consumer
     */
    BOOL _unread;
}

/*
 * factory method to generate blank DMX received message
 */
+(LXDMXReceivedMessage*) LXDMXReceivedMessage;
/*
 * factory method to generate DMX received message given a pointer to an array of level data and a length
 */
+(LXDMXReceivedMessage*) LXDMXReceivedMessage:(unsigned char*) msg length:(int) len;

/*
 * copies level data from an array
 */
-(void) readFromIncomingMessage:(unsigned char*) msg length:(int) len;
/*
 * copies level data and universe from another LXDMXReceivedMessage object
 */
-(void) readFromDMXReceivedMessage:(LXDMXReceivedMessage*) msg;

/*
 * pointer to the array of DMX level data
 */
-(unsigned char*) DMXArrayForRead;
/*
 * number of slots of data up to full universe of 512
 */
-(int) dmxArraySize;

/*
 * zero based universe number of the received DMX data
 */
-(int) receivedUniverse;
/*
 * set the universe number of the received DMX data (first universe index is zero)
 */
-(void) setReceivedUniverse:(int) u;

/*
 * flag indicating that the data in this message has been read by a consumer
 */
-(BOOL) unread;
/*
 * set the flag indicating that the data in this message has been read by a consumer
 */
-(void) setUnread:(BOOL) b;

@end
