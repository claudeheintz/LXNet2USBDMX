//
//  LXDMXReceivedMessage.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 9/27/10.
//  Copyright 2010-2016 Claude Heintz Design. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "LXDMXReceivedMessage.h"


@implementation LXDMXReceivedMessage

-(id) init {
	self = [super init] ;
	
	if ( self ) {
		_unread = NO;
	}
	
	return self;
}

-(id) initWithMessage:(unsigned char*) msg length:(int) len {
	self = [super init] ;
	
	if ( self ) {
		_unread = NO;
		[self readFromIncomingMessage:msg length:len];
	}
	
	return self;
}

+(LXDMXReceivedMessage*) LXDMXReceivedMessage {
	LXDMXReceivedMessage* newmsg = [[LXDMXReceivedMessage alloc] init];
	return newmsg;
}

+(LXDMXReceivedMessage*) LXDMXReceivedMessage:(unsigned char*) msg length:(int) len {
	LXDMXReceivedMessage* newmsg = [[LXDMXReceivedMessage alloc] initWithMessage:msg length:len];
	return newmsg;
}

-(void) readFromIncomingMessage:(unsigned char*) msg length:(int) len {
	@synchronized(self) {
	int n;
		int nm = len;
		if ( nm > DMX_DIMMERS_IN_UNIVERSE ) {
			nm = DMX_DIMMERS_IN_UNIVERSE;
		}
		
		for (n=0; n<DMX_DIMMERS_IN_UNIVERSE; n++) {    //future may include start code
            if ( n<nm ) {
                _slotsData[n] = msg[n];
            } else {
                _slotsData[n] = 0;              //zero others as insurance
            }
		}
		_slotsLength = nm;
		_unread = YES;
	}
}

-(void) readFromDMXReceivedMessage:(LXDMXReceivedMessage*) msg {
	@synchronized(msg) {
		[self readFromIncomingMessage:[msg DMXArrayForRead] length:[msg dmxArraySize]];
		[self setReceivedUniverse:[msg receivedUniverse]];
		[msg setUnread:NO];
        _unread = YES;
	}
}

-(unsigned char*) DMXArrayForRead {
	return _slotsData;
}

-(int) dmxArraySize {
	return _slotsLength;
}

-(int) receivedUniverse {
	return _universeindex;
}

-(void) setReceivedUniverse:(int) u {
	_universeindex = u;
}

-(BOOL) unread {
	return _unread;
}

-(void) setUnread:(BOOL) b {
	_unread = b;
}


@end
