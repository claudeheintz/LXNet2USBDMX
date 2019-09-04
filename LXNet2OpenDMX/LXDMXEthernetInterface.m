//
//  LXDMXEthernetInterface.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 12/3/09.
//  Copyright 2009-2016 Claude Heintz Design. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "LXDMXEthernetInterface.h"
#import "LXDMXReceivedMessage.h"
#import "CTUtility.h"
#import "CTNetUtilities.h"
#include <sys/socket.h>
#include <sys/_select.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <termios.h>
#include <arpa/inet.h>
#import "CTStatusReporter.h"
#import "LXDMXEthernetConfig.h"
#import "LXDMXCommonInclude.h"

LXDMXEthernetInterface* _sharedDMXEthernetInterface = NULL;

@implementation LXDMXEthernetInterface

@synthesize listPollResults;
@synthesize config;

-(id) initWithConfig:(LXDMXEthernetConfig*) econfig {
	self = [super init];
	if ( self ) {
		_lfd = -1;
		_bfd = -1;
        self.config = econfig;
		_sequence = 0;
        [self validateSACNPriority];
		_sthreadLock = [[NSLock alloc] init];
        _closing = NO;
        _zero = NO;
		_readpending = NO;
		_readdirty = NO;
        _local_listenenabled = (config.inprotocol != config.outprotocol ); //new 2/21/15 ok to have local listen as long as not same protocol which could create a loop
		_writing_to_buffer = NO;
        
        self.listPollResults = NO;
		
		[self setCurrentDMXReceivedMessage:[LXDMXReceivedMessage LXDMXReceivedMessage]];
		[self setPendingDMXReceivedMessage:[LXDMXReceivedMessage LXDMXReceivedMessage]];
        _currentReceivedMessageU2 = NULL;
        _pendingReceivedMessageU2 = NULL;   //create these with set receive two universes
	}
	return self;
}

int addressFrom4() {
	return 0;
}

+(LXDMXEthernetInterface*) sharedDMXEthernetInterface {
	return _sharedDMXEthernetInterface;
}

+(void) initSharedInterfaceWithConfig:(LXDMXEthernetConfig*) econfig {
	if ( ! _sharedDMXEthernetInterface ) {
        _sharedDMXEthernetInterface = [[LXDMXEthernetInterface alloc] initWithConfig:econfig];
	}
}

+(void) closeSharedDMXEthernetInterface {
	if ( _sharedDMXEthernetInterface ) {
        [_sharedDMXEthernetInterface setClosing:YES];
		[_sharedDMXEthernetInterface stopListening];
		[_sharedDMXEthernetInterface stopSending];
		[_sharedDMXEthernetInterface closeSendSocket];
		_sharedDMXEthernetInterface = NULL;
	}
}

+(void) shutdownSharedDMXEthernetInterface {
    if ( _sharedDMXEthernetInterface ) {
        if ( [_sharedDMXEthernetInterface isSending] ) {
            [_sharedDMXEthernetInterface zeroBuffer];
        }
    }
}

+(void) closeSharedDMXEthernetInterfaceForReset {
    if ( _sharedDMXEthernetInterface ) {
        [_sharedDMXEthernetInterface setClosing:YES];
        [_sharedDMXEthernetInterface stopListening];
        [_sharedDMXEthernetInterface stopSending];
        [_sharedDMXEthernetInterface closeSendSocket];
        while ( [_sharedDMXEthernetInterface listeningThread] ) {
            [NSThread sleepForTimeInterval:0.5];
        }
        while ( [_sharedDMXEthernetInterface sendingThread] ) {
            [NSThread sleepForTimeInterval:0.5];
        }
        
        _sharedDMXEthernetInterface = NULL;
    }
}

#pragma mark DMXMessage Methods


-(unsigned char*) DMXArrayForRead {					//input only read from message buffer
	return &_messagein[[self dmxStartIndexForProtocol:self.config.inprotocol]];
}

-(int) dmxArraySize {	//for input only
	return _dmxmaxin;
}


-(int) dmxStartIndexForProtocol:(int) p {   //universe is zero based
	if ( p < 2 ) {
		return ARTNET_ARTDMX_DATA_INDEX;
	}
	return SACN_DMX_DATA_INDEX;
}

-(void) updateSequenceForPage:(int) page {
    int offset = page * MESSAGE_OUT_PAGE_SIZE;
    if ( self.config.outprotocol < 2 ) {
        _messageout[12+offset] = [self packetSequenceNumber];
    } else {
        _messageout[111+offset] = [self packetSequenceNumber];
    }
}

-(void) addHeaderToDMXMessageForPage:(int) page {
    int offset = page * MESSAGE_OUT_PAGE_SIZE;
	if ( config.outprotocol < 2 ) {
		[LXDMXEthernetInterface setArtNetStringToBytes:&_messageout[0+offset]];
		packInt16Little(&_messageout[8+offset], 0x5000);	//dmx opcode l/h bytes8/9
		_messageout[10+offset] = 0;     //version hi
		_messageout[11+offset] = 14;    //version low
		//_messageout[12+offset] = [self packetSequenceNumber]; updated before each send
		_messageout[13+offset] = 0;     //physical
		_messageout[14+offset] = ((config.outuniverse & 0x0f) + page + ((config.outsubnet & 0x0f)<<4)); //low byte of Port-Address
		_messageout[15+offset] = ((config.outsubnet >> 8) & 0x7f); //high byte of port-address which = "Net + Subnet + Universe"
        packInt16Big(&_messageout[16+offset], DMX_DIMMERS_IN_UNIVERSE);	//dmx count h/l bytes 16&17
	} else {
		int i;
		int hend = [self dmxStartIndexForProtocol:config.outprotocol]; //should be 126 so last 0x00 is _messageout[125] the start code before slots
		for (i=0; i<hend; i++) {
			_messageout[i+offset] = 0x00;
		}
	//Root Layer
		_messageout[1+offset] = 0x10;		//_messageout[0] & _messageout[1] are preamble size _messageout[0] is always 0 as set above
        strcpy((char*)&_messageout[4+offset], "ASC-E1.17");//pad 0's to even 4byte multiple +13,+14,+15 (set above)
		uint16_t flagsPlusLength = 0x7000 + DMX_DIMMERS_IN_UNIVERSE + 110;
		packInt16Big(&_messageout[16+offset], flagsPlusLength);
		_messageout[21+offset] = 0x04;	//vector18,19,20=0x00
		int ui;
		NSArray* ua = [LXDMXEthernetInterface UUIDArray];
		for (ui=0; ui<16; ui++) {
			_messageout[22+ui+offset] = [[ua objectAtIndex:ui] intValue];
		}
	//Framing Layer
		flagsPlusLength = 0x7000 + DMX_DIMMERS_IN_UNIVERSE + 88;
		packInt16Big(&_messageout[38+offset], flagsPlusLength);
		_messageout[43+offset] = 0x02;	//vector indicates framing wraps DMP
		_messageout[44+offset] = 'L';
		_messageout[45+offset] = 'X';
		_messageout[46+offset] = 'C';
		_messageout[47+offset] = 'o';
		_messageout[48+offset] = 'n';
		_messageout[49+offset] = 's';
		_messageout[50+offset] = 'o';
		_messageout[51+offset] = 'l';
		_messageout[52+offset] = 'e';		//null terminated/padded
		_messageout[108+offset] = self.config.acnPriority;	//priority (109-110 reserved=0)
		//_messageout[111+offset] = [self packetSequenceNumber]; updated before each send
		_messageout[113+offset] = config.outsubnet;
		_messageout[114+offset] = config.outuniverse + page;
		
	//DMP Layer
		flagsPlusLength = 0x7000 + DMX_DIMMERS_IN_UNIVERSE + 11;
		packInt16Big(&_messageout[115+offset], flagsPlusLength);
		_messageout[117+offset] = 0x02;	//indicates a DMP Set Property message
		_messageout[118+offset] = 0xa1;	//type of data
		_messageout[122+offset] = 0x01;	//address increment
		packInt16Big(&_messageout[123+offset], DMX_DIMMERS_IN_UNIVERSE+1);  //added +1 for start code 9/25/13
		_messageout[125+offset] = 0x00;	//start code 
	}
}

-(void) addHeaderToDMXMessage {
    [self addHeaderToDMXMessageForPage:0];
    if ( _dmxmaxout > DMX_DIMMERS_IN_UNIVERSE ) {
       [self addHeaderToDMXMessageForPage:1];
    }
}

-(int) packetSequenceNumber {
	_sequence++;
	if ( _sequence > 255 ) {
		_sequence = 1;
	}
	return _sequence;
}

-(void) validateSACNPriority {
	if  ( config.acnPriority <= 0 ) {
		config.acnPriority = 100;
	} else if ( config.acnPriority > 200 ) {
		config.acnPriority = 200;
    }
}

-(void) forceUnicastAddressForPage:(int) page {
    NSString* unicaststr = NULL;
    if ( config.unicast ) {
        unicaststr = config.unicastAddress;
        if ( [unicaststr length] == 0 ) {
            unicaststr = NULL;
        }
    }
    if ( unicaststr ) {
        their_addr.sin_addr.s_addr = inet_addr([unicaststr cStringUsingEncoding:NSASCIIStringEncoding]);
    } else {
        if ( (config.outprotocol == DMX_TYPE_ARTNET10 ) || ( config.outprotocol == DMX_TYPE_ARTNET2 ) ) {
            if ( ! _defaultBroadcast ) {
                [self findDefaultBroadcastAddress];
            }
            if ( _defaultBroadcast ) {
                their_addr.sin_addr.s_addr = inet_addr([_defaultBroadcast cStringUsingEncoding:NSASCIIStringEncoding]);
            } else {
                their_addr.sin_addr.s_addr = inet_addr("127.0.0.1");    // fallback to local
            }
        } else if ( config.outprotocol == DMX_TYPE_SACN ) {
           their_addr.sin_addr.s_addr = inet_addr([[LXDMXEthernetInterface getNetIPStringForProtocol:2 subnet:config.outsubnet universe:config.outuniverse+page] cStringUsingEncoding:NSASCIIStringEncoding]);
        }
    }
}

#pragma mark receive options

-(int) receivedUniverse {
	return _receiveduniverse;
}

-(void) setEnableDMXIn:(BOOL) rx {
	_dmxinputenabled = rx;		//dmx input enabled because artnet is already listening for poll
    if ( rx ) {
        [self startListening];
        if (( config.inprotocol == DMX_TYPE_ARTNET10 ) || ( config.inprotocol == DMX_TYPE_ARTNET2 )) {
            if ( rx ) {
                [self sendArtNetReply]; //let network know you are now listening
            }
        }
    } else {
        [self stopListening];
    }
}

-(void) setEnableLocalListen:(BOOL) b {
    _local_listenenabled = b;
}

-(void) setReceiveTwoUniverses:(BOOL) twou  {
    if ( twou ) {
        [self setCurrentDMXReceivedMessageU2:[LXDMXReceivedMessage LXDMXReceivedMessage]];
        [self setPendingDMXReceivedMessageU2:[LXDMXReceivedMessage LXDMXReceivedMessage]];
    } else {
        [self setCurrentDMXReceivedMessageU2:NULL];
        [self setPendingDMXReceivedMessageU2:NULL];
    }
}

-(void) postDMXEthernetConfigChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LXDMX_ETHERNET_CONFIG_CHANGE object:self.config];
}

-(void) configChanged {
    [self performSelectorOnMainThread:@selector(postDMXEthernetConfigChanged) withObject:NULL waitUntilDone:NO];
}

/*  setInputUniverseAddress from Art-Net ArtAddress
    Art-Net Universe is low nibble of config.inuniverse
*/

-(void) setInputUniverseAddress:(unsigned char) u {
    if ( u != 0x7f ) {
        if ( (u & 0x80) != 0 ) {
            config.inuniverse = ( config.inuniverse & 0xf0 ) | (u & 0x07);
            [self configChanged];
        }
    }
}

/*  setInputSubnetAddress from  Art-Net ArtAddress
    Art-Net Subnet is low nibble of config.insubnet = __ __ nn _s
*/
-(void) setInputSubnetAddress:(unsigned char) s {
    if ( s != 0x7f ) {
        if ( (s & 0x80) != 0 ) {
            config.insubnet = ( config.insubnet & 0x7f00 ) | (s & 0x07);
            [self configChanged];
        }
    }
}

/*  setInputNetAddress from  Art-Net ArtAddress
    Art-Net Net is 7bits of 2nd byte of config.insubnet = __ __ nn _s
*/

-(void) setInputNetAddress:(unsigned char) s {
    if ( s != 0x7f ) {
        if ( (s & 0x80) != 0 ) {
            config.insubnet = ((s & 0x7f) << 8);
            [self configChanged];
        }
    }
}

#pragma mark Socket Methods


-(int) createAndBindSocketForProtocol:(int) protocol {	//used for listen socket
    int fd;	//BSD socket file descriptor
    
	if((fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) > 0) {		// AF_INET   SOCK_DGRAM
        if ( protocol != DMX_TYPE_SACN ) {
            int broadcast = 1;
            // this call is what allows broadcast packets to be sent:
            if (setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast,
                           (socklen_t)sizeof broadcast) == -1) {

                [CTStatusReporter reportStatus:@"Could not set socket to broadcast." level:CT_STATUS_LEVEL_RED];
                [CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding] level:CT_STATUS_LEVEL_RED];

            }
        }
        
		int yes = 1;
		setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, (socklen_t)sizeof(int));
		setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, (socklen_t)sizeof(int));
        
        recv_addr.sin_family = AF_INET;
        if ( protocol == DMX_TYPE_SACN ) {
            recv_addr.sin_port = htons(SACN_PORT);
        } else {
            recv_addr.sin_port = htons(ARTNET_PORT);
        }
        recv_addr.sin_addr.s_addr = htonl(INADDR_ANY);    //autoselect uses INADDR_ANY
        memset(recv_addr.sin_zero, '\0', sizeof recv_addr.sin_zero);
        
		
		if ( bind ( fd, (struct sockaddr*) &recv_addr, (socklen_t)sizeof(recv_addr) ) < 0 ) {
			[CTStatusReporter reportStatus:@"Failed to bind input socket." level:CT_STATUS_INFORM_USER_RED];
			[CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding] level:CT_STATUS_INFORM_USER_RED];
			close(fd);
			return -1;
		}

		if ( protocol == 2 ) {  //hard coded to one universe starting with config.inuniverse
			struct ip_mreq mreq;
            int minu = config.inuniverse - 1;
            int maxu = config.inuniverse;       //+1 for two universes
			
			int umi;
			for ( umi=minu; umi<maxu; umi++) {
				mreq.imr_multiaddr.s_addr = inet_addr([[LXDMXEthernetInterface getNetIPStringForProtocol:2 subnet:config.insubnet universe:1+umi] cStringUsingEncoding:NSASCIIStringEncoding]);
				mreq.imr_interface.s_addr = htonl(INADDR_ANY);
				
				if (setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq,
							   (socklen_t)sizeof mreq) == -1) {
					[CTStatusReporter reportStatus:@"Input socket settings error." level:CT_STATUS_INFORM_USER_RED];
					[CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding] level:CT_STATUS_LEVEL_RED];
					close(fd);
					return -1;
				}
			}
		}
		
        [CTStatusReporter reportStatus:@"Input socket OK" level:CT_STATUS_LEVEL_NOLOG_GREEN];
		return fd;	//succeeded in creating
	}
	
	[CTStatusReporter reportStatus:@"Failed to create input socket." level:CT_STATUS_INFORM_USER_RED];
	[CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding]  level:CT_STATUS_LEVEL_RED];
	
	return -1;
}

-(int) createAndBindBroadcastSocket {
	int sockfd;
    [CTStatusReporter reportStatus:@"Creating output socket."  level:CT_STATUS_LEVEL_INFO];
	
	if ((sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) == -1) {
        [CTStatusReporter reportStatus:@"Failed to create output socket." level:CT_STATUS_INFORM_USER_RED];
        [CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding] level:CT_STATUS_LEVEL_RED];
		return-1;
	}
	
	if ( config.outprotocol != DMX_TYPE_SACN ) {
		int broadcast = 1;
		// this call is what allows broadcast packets to be sent:
		if (setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &broadcast,
					   (socklen_t)sizeof broadcast) == -1) {
            [CTStatusReporter reportStatus:@"DMX socket settings error." level:CT_STATUS_LEVEL_RED];
            [CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding] level:CT_STATUS_LEVEL_RED];
			close(sockfd);
			return -1;
		}
	}
	int yes = 1;
	setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, (socklen_t)sizeof(int));
	setsockopt(sockfd, SOL_SOCKET, SO_REUSEPORT, &yes, (socklen_t)sizeof(int));
    
    in_addr_t bind_addr;
    send_addr.sin_family = AF_INET;
    if ( config.outprotocol == DMX_TYPE_SACN ) {
        send_addr.sin_port = htons(SACN_PORT);
        bind_addr = [config bindAddressForSACN];
    } else {
        send_addr.sin_port = htons(ARTNET_PORT);
        bind_addr = [config bindAddressForArtNet];
    }
    send_addr.sin_addr.s_addr = bind_addr;
    
    memset(send_addr.sin_zero, '\0', sizeof send_addr.sin_zero);
    
    BOOL fatalBindError = NO;
	if ( bind (sockfd, (struct sockaddr*) &send_addr, (socklen_t)sizeof(send_addr)) < 0 ) {
        if ( send_addr.sin_addr.s_addr != htonl(INADDR_ANY) ) {

            [CTStatusReporter reportStatus:[NSString stringWithFormat:@"Could not to bind output socket to %s.", inet_ntoa(send_addr.sin_addr)] level:CT_STATUS_LEVEL_YELLOW];

            send_addr.sin_addr.s_addr = htonl(INADDR_ANY);
            if ( bind (sockfd, (struct sockaddr*) &send_addr, (socklen_t)sizeof(send_addr)  ) < 0 ) {
                fatalBindError = YES;
            }
        } else {
            fatalBindError = YES;
        }
	}
    
    if ( fatalBindError ) {
        [CTStatusReporter reportStatus:@"Failed to bind dmx output socket." level:CT_STATUS_LEVEL_RED];
        [CTStatusReporter reportStatus:[NSString stringWithCString:strerror(errno) encoding:NSUTF8StringEncoding] level:CT_STATUS_LEVEL_RED];

        close(sockfd);
        return -1;
    }
    
    their_addr.sin_family = AF_INET;
    if ( config.outprotocol == DMX_TYPE_SACN) {
        their_addr.sin_port = htons(SACN_PORT);
        if ( bind_addr != INADDR_ANY ) {
            struct in_addr localInterface;
            localInterface.s_addr = bind_addr;
            if(setsockopt(sockfd, IPPROTO_IP, IP_MULTICAST_IF, (void *)&localInterface, sizeof(localInterface)) < 0) {
                [CTStatusReporter reportStatus:@"IP_MULTICAST_IF sockopt error."];
            }
        }
    } else {
        their_addr.sin_port = htons(ARTNET_PORT);
    }
    [self forceUnicastAddressForPage:0]; //first added 9/25/13  this sets up their_addr.sin_addr
	memset(their_addr.sin_zero, '\0', sizeof their_addr.sin_zero);	//useful??
    
    [CTStatusReporter reportStatus:@"DMX ethernet out OK" level:CT_STATUS_LEVEL_NOLOG_GREEN];
    
	return sockfd;
}


-(int) createListenSocket {
	if ( _lfd < 0 ) {
		_lfd = [self createAndBindSocketForProtocol:config.inprotocol];
	}
	return _lfd;
}

-(void) closeListenSocket {
	if ( _lfd > 0 ) {
		close(_lfd);
		_lfd = -1;
	}
}

-(void) createSendSocket {
    if ( _creating_socket ) {
        return;
    }
    _creating_socket = YES;
	if ( _bfd < 0 ) {
		_bfd = [self createAndBindBroadcastSocket];
		if ( _bfd < 0 ) {
			[self sendingFailure:NULL];	//should have informed at point of error
		}
	}
    _creating_socket = NO;
}

-(void) closeSendSocket {
	if ( _bfd > 0 ) {
		close(_bfd);
		_bfd = -1;
	}
}

-(int) listenfd {
	return _lfd;
}

-(void) setListenFD:(int) fd {
	_lfd = fd;
}


-(int) connectionSetForRead:(int) fdescriptor  create:(BOOL) create {
    if (create && ( fdescriptor < 0 )) {
        [self createListenSocket];	//new 1_3_10  and modified 7/11/13 to test for <0 and only create listen then (is this needed??)
    }
	if ( fdescriptor >= 0 ) {
		fd_set readfds;//,writefds,exceptfds;
		struct timeval timeout;
		FD_ZERO(&readfds);	//masks
		//FD_ZERO(&writefds);
		//FD_ZERO(&exceptfds);
		FD_SET(fdescriptor,&readfds);
		
		// Set the timeout - .005 second --assumes polling rather than waiting
		timeout.tv_sec = 0;
		timeout.tv_usec = 500;
		
		if ( select(fdescriptor+1,&readfds,nil,nil,&timeout) < 0 ) {
            [CTStatusReporter reportStatus:@"LXDMXEthernetInterface select() error\n" level:CT_STATUS_LEVEL_RED];
            [NSThread sleepForTimeInterval:1];
            return 0;
        }
		
		return FD_ISSET(fdescriptor, &readfds);
	}
	return 0;
}

#pragma mark broadcast address

-(void) findDefaultBroadcastAddressIfNeeded {
    if ( ! _defaultBroadcast ) {
        [self findDefaultBroadcastAddress];
    }
}

-(void) findDefaultBroadcastAddress {   // applies only to Art-Net
    _defaultBroadcast = NULL;   //set to null first for threading?
    
    BOOL wasset = NO;
    // if bound to specific address, try to match broadcast to that address
    if ( send_addr.sin_addr.s_addr != htonl(INADDR_ANY) ) {
        NSString* sendif = [NSString stringWithUTF8String:inet_ntoa(send_addr.sin_addr)];
        _defaultBroadcast = getBroadcastAddressForAddress(sendif);
        if ( _defaultBroadcast ) {
            wasset = YES;
        }
    }
    
    // look for address to use priority is one matching 2 or 10
    // next is one set in prefered popup (even if autoselect is enabled)
    // finally default to local host 127.0.0.1
    
    if ( ! wasset ) {
        NSString* addr;
        if ( config.outprotocol == DMX_TYPE_ARTNET2 ) {
            addr = [LXDMXEthernetInterface findNonLocalAddressWithPrefix:@"2" orAddress:config.artnetBindAddress];
        } else {
            addr = [LXDMXEthernetInterface findNonLocalAddressWithPrefix:@"10" orAddress:config.artnetBindAddress];
        }
        
        if ( addr ) {
            _defaultBroadcast = getBroadcastAddressForAddress(addr);
            if ( _defaultBroadcast ) {

                wasset = YES;
            }
        }
    }
    
    if ( ! wasset ) {
        _defaultBroadcast = [NSString stringWithFormat:@"127.0.0.1"];
        [CTStatusReporter reportStatus:@"No external ethernet connection for output." level:CT_STATUS_LEVEL_YELLOW];
    }
    
    [CTStatusReporter reportStatus:[NSString stringWithFormat:@"ethernet broadcast address: %@", _defaultBroadcast] level:CT_STATUS_LEVEL_INFO];
}

-(NSString*) defaultBroadcastAddress {
    return _defaultBroadcast;
}


+(NSString*) findIPInterfaceFor:(NSString*) astr {
	NSArray* addrarr = getNetIPAddresses();             //9-29-15

	NSString* ipaddr;
	NSRange colonrng;
	
	for ( ipaddr in addrarr ) {
		colonrng = [ipaddr rangeOfString:@":"];		//colon indicates IP6 address
		if ( colonrng.location != NSNotFound ) {
			continue;
		}
		if ( [ipaddr hasPrefix:astr] ) {
			return ipaddr;
		}
	}
	
	return NULL;
}

+(NSString*) findNonLocalAddressWithPrefix:(NSString*) astr orAddress:(NSString*) paddress {
    NSArray* addrarr = getNetIPAddresses();             //9-29-15
    
    NSString* foundaddr = NULL;
    NSString* nonLocaladdr = NULL;
    NSString* ipaddr;
    NSRange colonrng;
    
    for ( ipaddr in addrarr ) {
        colonrng = [ipaddr rangeOfString:@":"];		//colon indicates IP6 address
        if ( colonrng.location != NSNotFound ) {
            continue;
        }
        if ( [ipaddr hasPrefix:astr] ) {        //match prefix--we got what we want!
            foundaddr = ipaddr;
            break;
        } else if ( paddress && [ipaddr isEqualToString:paddress] ) {
            foundaddr = ipaddr;                         //matches preferred
        } else if ( ! [ipaddr hasPrefix:@"127"] ) {
            nonLocaladdr = ipaddr;                      //non-local
        }
    }
    if ( ! foundaddr ) {                                //not matching preferred or prefix
        foundaddr = nonLocaladdr;
    }
    
    return foundaddr;
}

+(BOOL) hostHasAddress:(NSString*) taddr {
	NSArray* addrarr = getNetIPAddresses();             //9-29-15
	NSString* ipaddr;
	
	for ( ipaddr in addrarr ) {
		if ( [ipaddr isEqualToString:taddr] ) {
			return YES;
		}
	}
	
	return NO;
}

#pragma mark listen thread methods

-(NSThread*) listeningThread {
	return _listenthread;
}

-(void) setListeningThread:(NSThread*) thread {
	_listenthread = thread;
}

-(BOOL) isListening {
	return _listening;
}

-(void) setListening:(BOOL) l {
	_listening = l;
}

-(void) startListening {
	[self setListening:YES];
	if ( ! [self listeningThread] ) {
		[NSThread detachNewThreadSelector:@selector(listen:) toTarget:self withObject:self];
	}
}

-(void) stopListening {
	if ( [self isListening] ) {
		[self setListening:NO];
		if ( [NSThread currentThread] != [self listeningThread] ) {
			
		} else {
			[self closeListenSocket];
		}
	}
}

- (void)listen:(id) anObject {
    [[NSThread currentThread] setName:@"DMX Listen"];
	[self setListeningThread:[NSThread currentThread]];
	
	[self createListenSocket];
	double min_sleep = 0.025;	//smallest dmx frame time
	
	if ( [self listenfd] > 0 ) {
		while ( [self isListening] ) {
			[self readAMessage];
			
			if ( _dmxinputenabled ) {
				if ( [[self currentDMXReceivedMessage] unread] ) {
					min_sleep = 0.1;	//allow more time of main thread to catch up  (U2 still could be unread)
				} else {
					min_sleep = 0.025;
				}
			} else {
				min_sleep = 1.5;
			}
			
			[NSThread sleepForTimeInterval:min_sleep];
		}
	}
	
	[self closeListenSocket];
	[self setListeningThread:NULL];
}

- (void) readAMessage {
    if ( [self connectionSetForRead:_lfd create:YES] != 0 ) {
		int len =1000;
		int result;
		unsigned int flags = 0;
		fromlen = (int) sizeof _clientAddress;
		
		while ( [self isListening] && ( [self connectionSetForRead:_lfd  create:YES] != 0 ) ) {	//keep reading until buffer is empty
			result =  (int) recvfrom([self listenfd], _messagein, len, flags, (struct sockaddr *)&_clientAddress, &fromlen);

			if ( result > 0 ) {
				_messagelength = result;
				if ( config.inprotocol < 2 ) {
					[self receivedArtNetMessage:&_messagein[0] length:_messagelength readDMX:YES];
				} else {
					[self receivedDMXOverEthernetMessage];
				}
			} else if ( result == 0 ) {
				
			} else {
                [CTStatusReporter reportStatus:@"LXDMXEthernet recvfrom result negative!" level:CT_STATUS_LEVEL_LOG];
			}
		}
	}
}

#pragma mark Art-Net Listen on output loop

//this is used on send loop from bradcastDMX to read available Art-Net packets looking for poll replies

- (void) readAvailableArtNetPacketsFromBroadcastSocket {
    if ( [self connectionSetForRead:_bfd create:NO] != 0 ) {
        int len =1000;
        int result;
        unsigned int flags = 0;
        fromlen = (int) sizeof _clientAddress;
        BOOL readDMXOK = _dmxinputenabled && ((config.inprotocol == DMX_TYPE_ARTNET2) || (config.inprotocol == DMX_TYPE_ARTNET10));
        
        while ( [self isSending] && ( [self connectionSetForRead:_bfd create:NO] != 0 ) ) {	//keep reading until buffer is empty
            result =  (int) recvfrom(_bfd, _prmessage, len, flags, (struct sockaddr *)&_clientAddress, &fromlen);
            if ( result > 0 ) {
                [self receivedArtNetMessage:&_prmessage[0] length:result readDMX:readDMXOK];
            } else if ( result == 0 ) {
                
            } else {
                [CTStatusReporter reportStatus:@"LXDMXEthernet recvfrom result negative!" level:CT_STATUS_LEVEL_LOG];
            }
        }
    }
}


#pragma mark message methods

-(void) printMessage:(unsigned char*)mbytes  length:(int) mlength {
	int nn;
	printf(" _____________ received message from family %i, address %s\n", _clientAddress.sin_family, inet_ntoa(_clientAddress.sin_addr));
	for ( nn=0; nn<mlength; nn++) {
		printf("%i = %i  %c\n", nn, mbytes[nn], mbytes[nn]);
	}
}

-(void) receivedArtNetMessage:(unsigned char*) mbytes length:(int) mlength readDMX:(BOOL) readOK {
	BOOL echo = NO;                //set to yes for diagnostics
    //_local_listenenabled = YES;  //may also want this if testing locally
    
	if (( mlength > 11 ) && ( mbytes[7] == 0 )) {
		NSString* artnetstr = [NSString stringWithCString:(char*)mbytes encoding:NSUTF8StringEncoding];
		if ( [artnetstr isEqualToString:@"Art-Net"] ) {
			int opcode = mbytes[8] + mbytes[9]*256;
            [CTStatusReporter reportStatus:[NSString stringWithFormat:@"Art-Net message length %i opcode %x received from %s", mlength, opcode, inet_ntoa(_clientAddress.sin_addr)] flag:echo];
            
			if ( opcode == ARTNET_ARTPOLL ) {
                [CTStatusReporter reportStatus:[NSString stringWithFormat:@"Art Net Poll protocol version %i %i params %i %i",  _messagein[10], _messagein[11], mbytes[12], mbytes[13]] flag:echo];
                // reply to poll no matter who sent it
                //   broadcast reply even if we sent the poll
                [self sendArtNetReply];
                
			} else {    // opcode != ARTNET_ARTPOLL -> other than art-net poll
                
                // these next tests check to see if we are talking to ourself and return, ignoring our own babble
                
				if ( equalSocketAddr(_clientAddress, send_addr) ) {	//sent from us and not a poll == return
                    [CTStatusReporter reportStatus:@"Recieved from self." flag:echo];
					return;
				}
                
                if ( htonl(INADDR_ANY) == send_addr.sin_addr.s_addr ) {
					if (( config.inprotocol == DMX_TYPE_ARTNET10 ) || ( config.inprotocol == DMX_TYPE_ARTNET2 ) || ( opcode == ARTNET_ARTPOLL_REPLY )) {
						if ( [LXDMXEthernetInterface hostHasAddress:[NSString stringWithCString:inet_ntoa(_clientAddress.sin_addr) encoding:NSUTF8StringEncoding]] ) {
                            [CTStatusReporter reportStatus:@"Recieved from self (2)." flag:echo];
                            if ( ! _local_listenenabled ) {
                                return;
                            }
						}
					} else {
                        [CTStatusReporter reportStatus:@"Ignoring Art-Net packet because no Art-Net input selected." flag:echo];
						return;
					}
				}
                
				if ( opcode == ARTNET_ARTDMX ) {   // opcode is ArtDMX
					[CTStatusReporter reportStatus:[NSString stringWithFormat:@"Art-DMX received subnet %i, net %i", mbytes[14]>>4, mbytes[15]] flag:echo];

					if ( _dmxinputenabled && readOK ) {		//_messagein[11] should >= 14 for protocol rev.
						if (( (mbytes[14] >> 4) == (config.insubnet & 0x0f) ) && ( mbytes[15] == ((config.insubnet >> 8 )& 0xff) )) {
							int receiveduniverse = mbytes[14] & 0xff;
							
                            [CTStatusReporter reportStatus:[NSString stringWithFormat:@"Art-DMX received universe %i", receiveduniverse] flag:echo];
							
							if ( receiveduniverse == config.inuniverse ) {   // 5-23-14 added next universe
                                _receiveduniverse = receiveduniverse;
								_dmxmaxin = mbytes[16] * 256 + mbytes[17];  //crosscheck uses smaller packet size
                                int crosscheck = _messagelength - [self dmxStartIndexForProtocol:config.inprotocol];
                                if ( crosscheck < _dmxmaxin ) {
                                    _dmxmaxin = crosscheck;
                                }
                                
                                if (_dmxmaxin > 512) {
                                    _dmxmaxin = 512;            //restrict to single universe at most
                                }
                                
                                if ( _readpending ) {
                                    [self readToPendingDMXReceivedMessage:&mbytes[[self dmxStartIndexForProtocol:config.inprotocol]]];
                                    _readdirty = YES;           //when YES, postDMXMessageReceived thread will keep posting to main thread
                                } else {
                                     _readdirty = NO;
                                     _readpending = YES;
                                    [self readToCurrentDMXReceivedMessage:&mbytes[[self dmxStartIndexForProtocol:config.inprotocol]]];
                                     [NSThread detachNewThreadSelector:@selector(postDMXMessageReceived) toTarget:self withObject:nil];
                                }
							} else if (( receiveduniverse == config.inuniverse+1 ) && (_currentReceivedMessageU2 != NULL)) {
                                _receiveduniverse2 = receiveduniverse;
                                _dmxmaxin2 = mbytes[16] * 256 + mbytes[17];  //no cross checking with packet size here!!!
                                int crosscheck = _messagelength - [self dmxStartIndexForProtocol:config.inprotocol];
                                if ( crosscheck < _dmxmaxin2 ) {
                                    _dmxmaxin2 = crosscheck;
                                }
                                if (_dmxmaxin2 > 512) {
                                    _dmxmaxin2 = 512;            //restrict to single universe at most
                                }
								
                                if ( _readpendingU2 ) {
                                    _readdirtyU2 = YES;
                                    [self readToPendingDMXReceivedMessageU2:&mbytes[[self dmxStartIndexForProtocol:config.inprotocol]]];
                                } else {
                                    _readdirtyU2 = NO;
                                    _readpendingU2 = YES;
                                    [self readToCurrentDMXReceivedMessageU2:&mbytes[[self dmxStartIndexForProtocol:config.inprotocol]]];
                                    [NSThread detachNewThreadSelector:@selector(postDMXMessageReceivedU2) toTarget:self withObject:nil];
                                }
                            }
						}       // end matched subnet nibble
					}           // end _dmxinputenabled && readOK
                                // end opcode is ArtDMX
				} else if ( opcode == ARTNET_ARTPOLL_REPLY ) {
                    if ( echo ) {
                        [CTStatusReporter reportStatus:[NSString stringWithFormat:@"Art Net Reply Received from %s", inet_ntoa(_clientAddress.sin_addr)]];
						[self printMessage:mbytes length:mlength];
					}
					if ( mbytes[19] == config.outsubnet ) {
                        NSString* shortname = [NSString stringWithCString:(const char*)&mbytes[26] encoding:NSUTF8StringEncoding];
                        if ( ! [shortname isEqualToString:config.shortName] ) {
                            if ( config.setUnicastFromReply) {
                                int replyaddr = ints2saddr(mbytes[10], mbytes[11], mbytes[12], mbytes[13]);
                                struct sockaddr_in tAddress;
                                tAddress.sin_addr.s_addr = replyaddr;
                                NSString* cipstr;
                                if ( replyaddr != 0 ) {
                                    cipstr = [NSString stringWithCString:inet_ntoa(tAddress.sin_addr) encoding:NSUTF8StringEncoding];
                                } else {
                                    cipstr = [NSString stringWithCString:inet_ntoa(_clientAddress.sin_addr) encoding:NSUTF8StringEncoding];
                                }
                                config.unicastAddress = cipstr;
                                [self configChanged];
                                if ( config.unicast ) {
                                    their_addr.sin_addr = _clientAddress.sin_addr;
                                }
                            }
                        }
					}
                    if ( self.listPollResults ) {
                        int replyaddr = ints2saddr(mbytes[10], mbytes[11], mbytes[12], mbytes[13]);
                        struct sockaddr_in tAddress;
                        tAddress.sin_addr.s_addr = replyaddr;
                        NSString* cipstr;
                        if ( replyaddr != 0 ) {
                            cipstr = [NSString stringWithCString:inet_ntoa(tAddress.sin_addr) encoding:NSUTF8StringEncoding];
                        } else {
                            cipstr = [NSString stringWithCString:inet_ntoa(_clientAddress.sin_addr) encoding:NSUTF8StringEncoding];
                        }
                        NSString* pollSummary = [NSString stringWithFormat:@"Art-Net Node: %@ %s", cipstr, &mbytes[44]];
                        [CTStatusReporter reportStatus:pollSummary level:CT_STATUS_LEVEL_INFO];
                    }
				} else if ( opcode == ARTNET_ARTADDRESS ) {
                    [self setInputUniverseAddress:mbytes[100]];
                    [self setInputSubnetAddress:mbytes[104]];
                    [self setInputNetAddress:mbytes[12]];           // Art-Net III Net+SubNet+Univ 15bits
                    
                    //also may want to allow name change
        
                } else if ( echo ) {
					[CTStatusReporter reportStatus:@"Unknown Art-Net message"];
					[self printMessage:mbytes length:mlength];
				}
			}
		} else if ( echo ) {
			[CTStatusReporter reportStatus:@"unknown message"];
			[self printMessage:mbytes length:mlength];
		}
	} else if ( echo ) {
		[CTStatusReporter reportStatus:@"unknown message"];
		[self printMessage:mbytes length:mlength];
	}
}

-(void) receivedDMXOverEthernetMessage {
	if ( _dmxinputenabled ) {
		BOOL printconnect = NO;

        if (( config.outprotocol == 2 ) && _sending ) {  //loop prevention
            if ( _clientAddress.sin_addr.s_addr == send_addr.sin_addr.s_addr ) {
                return;
            } else if ( 0 == send_addr.sin_addr.s_addr ) {
                if ( [LXDMXEthernetInterface hostHasAddress:[NSString stringWithCString:inet_ntoa(_clientAddress.sin_addr) encoding:NSUTF8StringEncoding]] ) {
                    return;
                }
            }
        }

		if ( _messagelength < 16 ) {
            [CTStatusReporter reportStatus:@"Error: RLP Packet Length" level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		if ( _messagein[1] != 0x10 ) {				//check protocol header  QUESTION ABOUT 0 based index?????
			[CTStatusReporter reportStatus:@"Error: RLP Preamble Size" level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		
		NSString* acnstr = [NSString stringWithCString:(char*)_messagein+4 encoding:NSUTF8StringEncoding];
		if ( ! [acnstr isEqualToString:@"ASC-E1.17"] ) {
			[CTStatusReporter reportStatus:[NSString stringWithFormat:@"Error: ACN Packet ID %s", [acnstr UTF8String]] level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		if ( printconnect ) {
			NSLog(@"Received acn packet length = %i\n", _messagelength);
		}
		int rootsizeflags = _messagein[16] * 256 + _messagein[17];
		if ( (0x7000 +_messagelength-16) != rootsizeflags ) {
			[CTStatusReporter reportStatus:[NSString stringWithFormat:@"Error: DMX over Ethernet Root flags/packet length %i, %i", (0x7000 +_messagelength-16), rootsizeflags] level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		int framingsizeflags = _messagein[38] * 256 + _messagein[39];
		if ( (0x7000 +_messagelength-38) != framingsizeflags ) {
            [CTStatusReporter reportStatus:@"Error: DMX over Ethernet Framing flags/packet length" level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		int dmpsizeflags = _messagein[115] * 256 + _messagein[116];
		if ( (0x7000 +_messagelength-115) != dmpsizeflags ) {
                [CTStatusReporter reportStatus:[NSString stringWithFormat:@"Error: DMX over Ethernet DMP flags/packet length %i should be %i", dmpsizeflags,(0x7000 +_messagelength-115)] level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		int addresscount = _messagein[123] * 256 + _messagein[124]; // number of addresses
		if ( (_messagelength-SACN_DMX_START_CODE_INDEX) != addresscount ) {               //was 126 prior to 9/25/13
			[CTStatusReporter reportStatus:@"Error: DMX over Ethernet address count/packet length" level:CT_STATUS_LEVEL_DEBUG];
			return;
		}
		
		if (( _messagein[113] == config.insubnet ) && (_messagein[SACN_DMX_START_CODE_INDEX] == 0 )) {  //match subnet and zero start code
			int receiveduniverse = _messagein[114]-1;	//Universe index starts with 1 not 0 as with artnet
            if ( receiveduniverse == config.inuniverse-1 ) {
                _receiveduniverse = receiveduniverse;
                _dmxmaxin = addresscount;
                
                if ( _dmxmaxin > DMX_DIMMERS_IN_UNIVERSE ) {
                    _dmxmaxin = DMX_DIMMERS_IN_UNIVERSE;
                }
                
                if ( printconnect ) {
                    printf("received dmx over ethernet for %i addresses!!! in universe %i\n", _dmxmaxin, _receiveduniverse);
                    //[self printMessage:_messagein length:_messagelength];
                }
                
                 if ( _readpending ) {
                     @synchronized(self) {      //7-7-16 added @synchronized when copying pending to current
                         _readdirty = YES;
                         [self readToPendingDMXReceivedMessage:&_messagein[[self dmxStartIndexForProtocol:config.inprotocol]]];
                     }
                 } else {
                     _readdirty = NO;
                     _readpending = YES;
                     [self readToCurrentDMXReceivedMessage:&_messagein[[self dmxStartIndexForProtocol:config.inprotocol]]];
                     [NSThread detachNewThreadSelector:@selector(postDMXMessageReceived) toTarget:self withObject:nil];
                 }
            } else if (( receiveduniverse == config.inuniverse ) && ([self currentDMXReceivedMessageU2] != NULL)) {
                _dmxmaxin2 = addresscount;
                _receiveduniverse2 = receiveduniverse;
                
                if ( _dmxmaxin2 > DMX_DIMMERS_IN_UNIVERSE ) {
                    _dmxmaxin2 = DMX_DIMMERS_IN_UNIVERSE;
                }
                
                if ( printconnect ) {
                    printf("received dmx over ethernet for %i addresses!!! in universe(2) %i\n", _dmxmaxin2, _receiveduniverse2);
                    //[self printMessage:_messagein length:_messagelength];
                }

                if ( _readpendingU2 ) {
                    @synchronized(self) {      //7-7-16 added @synchronized when copying pending to current
                        _readdirtyU2 = YES;
                        [self readToPendingDMXReceivedMessageU2:&_messagein[[self dmxStartIndexForProtocol:config.inprotocol]]];
                    }
                } else {
                    _readdirtyU2 = NO;
                    _readpendingU2 = YES;
                    [self readToCurrentDMXReceivedMessageU2:&_messagein[[self dmxStartIndexForProtocol:config.inprotocol]]];
                    [NSThread detachNewThreadSelector:@selector(postDMXMessageReceivedU2) toTarget:self withObject:nil];
                }
            }
		}
	}
}

-(LXDMXReceivedMessage*) currentDMXReceivedMessage {
    return _currentReceivedMessage;
}

-(void) setCurrentDMXReceivedMessage:(LXDMXReceivedMessage*) crm {
    _currentReceivedMessage = crm;
}

-(LXDMXReceivedMessage*) currentDMXReceivedMessageU2  {
    return _currentReceivedMessageU2;
}

-(void) setCurrentDMXReceivedMessageU2:(LXDMXReceivedMessage*) crm {
    _currentReceivedMessageU2 = crm;
}

-(void) readToCurrentDMXReceivedMessage:(unsigned char*) msg {
	[_currentReceivedMessage readFromIncomingMessage:msg length:_dmxmaxin];
	[_currentReceivedMessage setReceivedUniverse:_receiveduniverse];
}

-(void) readToCurrentDMXReceivedMessageU2:(unsigned char*) msg {
	[_currentReceivedMessageU2 readFromIncomingMessage:msg length:_dmxmaxin2];
	[_currentReceivedMessageU2 setReceivedUniverse:_receiveduniverse2];
}

-(LXDMXReceivedMessage*) pendingDMXReceivedMessage {
    return _pendingReceivedMessage;
}

-(void) setPendingDMXReceivedMessage:(LXDMXReceivedMessage*) crm {
    _pendingReceivedMessage = crm;
}

-(LXDMXReceivedMessage*) pendingDMXReceivedMessageU2 {
    return _pendingReceivedMessageU2;
}

-(void) setPendingDMXReceivedMessageU2:(LXDMXReceivedMessage*) crm {
    _pendingReceivedMessageU2 = crm;
}

-(void) readToPendingDMXReceivedMessage:(unsigned char*) msg {
	[_pendingReceivedMessage readFromIncomingMessage:msg length:_dmxmaxin];
	[_pendingReceivedMessage setReceivedUniverse:_receiveduniverse];
}

-(void) readToPendingDMXReceivedMessageU2:(unsigned char*) msg {
	[_pendingReceivedMessageU2 readFromIncomingMessage:msg length:_dmxmaxin2];
	[_pendingReceivedMessageU2 setReceivedUniverse:_receiveduniverse2];
}


-(void) postDMXMessageReceived {
	[self performSelectorOnMainThread:@selector(postCurrentDMXReceivedMessage) withObject:nil waitUntilDone:YES];
    
	while ( _readdirty ) {
        _readdirty = NO;
        @synchronized(self) {         //7-7-16 added @synchronized when setting pending
            [[self currentDMXReceivedMessage] readFromDMXReceivedMessage:[self pendingDMXReceivedMessage]];
        }
		[self performSelectorOnMainThread:@selector(postCurrentDMXReceivedMessage) withObject:nil waitUntilDone:YES];
	}
    _readpending = NO;  //allows creation of new posting thread
}

-(void) postDMXMessageReceivedU2 {
    [self performSelectorOnMainThread:@selector(postCurrentDMXReceivedMessageU2) withObject:nil waitUntilDone:YES];
    
	while ( _readdirtyU2 ) {
        _readdirtyU2 = NO;
        @synchronized(self) {                   //7-7-16 added @synchronized when setting pending
            [[self currentDMXReceivedMessageU2] readFromDMXReceivedMessage:[self pendingDMXReceivedMessageU2]];
        }
        [self performSelectorOnMainThread:@selector(postCurrentDMXReceivedMessageU2) withObject:nil waitUntilDone:YES];
	}
    _readpendingU2 = NO;  //allows creation of new posting thread
}

-(void) postCurrentDMXReceivedMessage {
    [[NSNotificationCenter defaultCenter] postNotificationName:LXDMX_RECEIVE_NOTIFICATION object:[self currentDMXReceivedMessage]];
	[[self currentDMXReceivedMessage] setUnread:NO];
}

-(void) postCurrentDMXReceivedMessageU2 {
    [[NSNotificationCenter defaultCenter] postNotificationName:LXDMX_RECEIVE_NOTIFICATION object:[self currentDMXReceivedMessageU2]];
	[[self currentDMXReceivedMessageU2] setUnread:NO];
}

#pragma mark sending methods

-(BOOL) isClosing {
    return _closing;
}

-(void) setClosing:(BOOL) s {
    _closing = s;
}

-(NSThread*) sendingThread {
	return _sendthread;
}

-(void) setSendingThread:(NSThread*) thread {
	_sendthread = thread;
}

-(BOOL) isSending {
	return _sending;
}

-(void) setSending:(BOOL) s {
	_sending = s;
}

-(void) startSending {
	[self setSending:YES];
	if ( ! [self sendingThread] ) {
		[NSThread detachNewThreadSelector:@selector(send:) toTarget:self withObject:self];
	}
}

-(void) stopSending {
	if ( [self isSending] ) {
		[self setSending:NO];
		if ( [NSThread currentThread] != [self sendingThread] ) {
			
		} else {
			[self closeSendSocket]; //??
		}
	}
}

- (void)send:(id) anObject {
	[self setSendingThread:[NSThread currentThread]];
	
	[self createSendSocket];
    BOOL keepAlive;
    
    id _activity = NULL;
    if ( [[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)] ) {
        NSActivityOptions options = NSActivityLatencyCritical | NSActivityUserInitiated;
        // NSActivityLatencyCritical   NSActivityUserInitiated 0x00FFFFFF  NSActivityUserInitiatedAllowingIdleSystemSleep
        _activity = [[NSProcessInfo processInfo] beginActivityWithOptions:options
                                                                    reason:@"Sending DMX over Ethernet"];
    }
	
	if ( _bfd > 0 ) {
		while ( [self isSending] ) {
            keepAlive = last_send_time + 1 < [NSDate timeIntervalSinceReferenceDate];
			if ( ! _writing_to_buffer ) {	//can skip because finishBufferWrite will call broadcastDMX
                if ( keepAlive ) {
                    [self broadcastDMX];
                }
			}
			if (( config.outprotocol == 1 ) || ( config.outprotocol == 0 )) {
                if ( keepAlive && (last_poll_time + 30 < [NSDate timeIntervalSinceReferenceDate]) ) {
                    if ( ! [self isClosing] ) {
                        self.listPollResults = NO;
                        [self broadcastArtNetPoll];
                    }
                }
			}
			_suspend_send_error = NO;
			[NSThread sleepForTimeInterval:1];
		}
	}
	_suspend_send_error = NO;
	[self closeSendSocket];
	[self setSendingThread:NULL];
    
    if ( _activity ) {
        if ( [[NSProcessInfo processInfo] respondsToSelector:@selector(endActivity:) ] ) {
            [[NSProcessInfo processInfo] endActivity:_activity];
        }
        _activity = NULL;
    }
}

-(void) setSuspendSendingErrorReporting:(BOOL) suspend {
    _suspend_send_error = suspend;
}

-(void) sendingFailure:(NSString*) message {
    if ( _suspend_send_error ) {
        [NSThread sleepForTimeInterval:0.25];  //wait and then just return and ignore the error;
        return;
    }
	[self setSending:NO];
    
	[[NSNotificationCenter defaultCenter] postNotificationName:@"StopReadingDMX" object:self];
	
	if ( message ) {
		[CTStatusReporter reportStatus:[NSString stringWithFormat:@"DMX Ethernet send failure.%@", message] level:CT_STATUS_LEVEL_RED];
	} else {
        [CTStatusReporter reportStatus:@"DMX Ethernet send failure." level:CT_STATUS_LEVEL_RED];
    }
    
    [LXDMXEthernetInterface closeSharedDMXEthernetInterface];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ethernetEnabledChanged" object:self];
}

-(void) artnetReplyFailure {	//changed to fail silently
	/*
	[self setSending:NO];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"StopReadingDMX" object:self];
	
	[LXDMXEthernetInterface closeSharedDMXEthernetInterface];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ethernetEnabledChanged" object:self];*/
}

-(void) broadcastArtNetPoll {
	if ( _bfd > 0 ) {
		unsigned char pollmessage[16];
		NSInteger numbytes;
		int n;
		for ( n=0; n < 16; n++ ) {
			pollmessage[n] = 0;
		}
		[LXDMXEthernetInterface setArtNetStringToBytes:&pollmessage[0]];
		packInt16Little(&pollmessage[8], ARTNET_ARTPOLL);	//opcode l/h bytes8/9
		pollmessage[10] = 0;	//protocol version h
		pollmessage[11] = 14;	//protocol version l
		pollmessage[12] = 6;	//talk to me flags
		pollmessage[13] = 0;	//diagnostic priority
				
		
		struct sockaddr_in bcast_addr = their_addr;
        if ( _defaultBroadcast ) {
            bcast_addr.sin_addr.s_addr = inet_addr([_defaultBroadcast cStringUsingEncoding:NSASCIIStringEncoding]);
        } else {
            if ( config.outprotocol == 1 ) {
                bcast_addr.sin_addr.s_addr = inet_addr("10.255.255.255");
            } else {
                bcast_addr.sin_addr.s_addr = inet_addr("2.255.255.255");
            }
        }
        
        /*
        uint8_t a = bcast_addr.sin_addr.s_addr & 0xff;
        uint8_t b = (bcast_addr.sin_addr.s_addr>>8) & 0xff;
        uint8_t c = (bcast_addr.sin_addr.s_addr>>16) & 0xff;
        uint8_t d = (bcast_addr.sin_addr.s_addr>>24) & 0xff;
        NSLog(@"poll to %i.%i.%i.%i", a,b,c,d);
        */
		
		[_sthreadLock lock];
		if ((numbytes=sendto(_bfd, pollmessage, 14, 0,
							 (struct sockaddr *)&bcast_addr, (socklen_t)sizeof bcast_addr)) == -1) {
            [CTStatusReporter reportStatus:@"Art-Net Poll failed to send"];
		}
		[_sthreadLock unlock];
        last_poll_time = [NSDate timeIntervalSinceReferenceDate];
	} else {
		[CTStatusReporter reportStatus:@"Art-Net:  no open fd to send poll\n"];
        last_poll_time = [NSDate timeIntervalSinceReferenceDate]-25;
	}
    //last_poll_time = [NSDate timeIntervalSinceReferenceDate];
}

-(void) sendArtNetReply {  //in aptly named because it replies to client address
	int bsock = -1;
	struct sockaddr_in reply_addr;
	struct sockaddr_in my_addr;
    my_addr.sin_addr.s_addr = 0;
    
    //  re-use existing socket -> must have received ArtNetPoll somehow...
    //  priority is to respond if listening to let network know destination is availables
    if ( [self isListening] && (config.inprotocol != DMX_TYPE_SACN) ) {
        bsock = _lfd;
        my_addr = recv_addr;
    } else if ( [self isSending] && (config.outprotocol != DMX_TYPE_SACN) ) {
        bsock = _bfd;
        my_addr = send_addr;
    } else {
        [CTStatusReporter reportStatus:@"no socket to send Art-Net reply."];
        return;
    }
    
    // if replying from socket bound to any_address, look for non-local matching client
    if ( my_addr.sin_addr.s_addr == 0 ) {
        NSString* addr = [NSString stringWithUTF8String:inet_ntoa(_clientAddress.sin_addr)];
        if ( addr ) {
            NSArray* arr = substringsUsingSeperator(addr, @".");
            
            if ( [arr count] == 4 ) {
                addr = [LXDMXEthernetInterface findNonLocalAddressWithPrefix:[arr objectAtIndex:0] orAddress:config.artnetBindAddress];
                if ( addr ) {
                    arr = substringsUsingSeperator(addr, @".");
                    if ( [arr count] == 4 ) {
                        my_addr.sin_addr.s_addr = ints2saddr([[arr objectAtIndex:0] intValue], [[arr objectAtIndex:1] intValue], [[arr objectAtIndex:2] intValue], [[arr objectAtIndex:3] intValue]);
                    }
                }
            }
        }
    }

    if ( bsock > 0 ) {
        reply_addr.sin_family = AF_INET;
        reply_addr.sin_port = htons(6454);
        packInt32Little(&listen_netaddr[0], _clientAddress.sin_addr.s_addr);
    
        // broadcast reply on client's network
        if ( listen_netaddr[0] == 10 ) {
            reply_addr.sin_addr.s_addr = inet_addr("10.255.255.255");
        } else if ( listen_netaddr[0] == 2 ) {
            reply_addr.sin_addr.s_addr = inet_addr("2.255.255.255");
        } else if ( listen_netaddr[0] == 127 ) {
            reply_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
        } else if ( listen_netaddr[0] == 169 ) {
            reply_addr.sin_addr.s_addr = ints2saddr(listen_netaddr[0], listen_netaddr[1], 255, 255);
        } else {
            reply_addr.sin_addr.s_addr = ints2saddr(listen_netaddr[0], listen_netaddr[1], listen_netaddr[2], 255);
        }
        memset(reply_addr.sin_zero, '\0', sizeof reply_addr.sin_zero);
        
        //get IPAddress to include in reply
        packInt32Little(&listen_netaddr[0], my_addr.sin_addr.s_addr);
	
		unsigned char replymessage[239];
		int n;
		for ( n=0; n < 239; n++ ) {
			replymessage[n] = 0;
		}
		[LXDMXEthernetInterface setArtNetStringToBytes:&replymessage[0]];
		packInt16Little(&replymessage[8], ARTNET_ARTPOLL_REPLY);	//opcode l/h bytes8/9
		replymessage[10] = listen_netaddr[0];	//ipv4 address
		replymessage[11] = listen_netaddr[1];
		replymessage[12] = listen_netaddr[2];
		replymessage[13] = listen_netaddr[3];
		packInt16Little(&replymessage[14], 0x1936);	//port l/h bytes 14/15
		replymessage[16] = 0;	//firmware h/l
		replymessage[17] = 0;
		replymessage[18] = 0;	//subnet address h/l
		replymessage[19] = config.outsubnet;
		replymessage[20] = 0;	//oem h/l
		replymessage[21] = 0;
		replymessage[22] = 0;	//ubea
		replymessage[23] = 0;	//status
		replymessage[24] = 0x50;     //esta manufacturer code  108,120 = claude heintz design, Arrtistic License 0x1250
		replymessage[25] = 0x12;     //seems DMX workshop reads these bytes backwards of string direction l/h
        strcpy((char*)&replymessage[26], [config.shortName cStringUsingEncoding:NSASCIIStringEncoding]);//short name 26+18=44
        
        NSString* bonjourName = [NSString stringWithFormat:@"%@@%@", config.shortName, [[NSHost currentHost] localizedName]];
        if ( [bonjourName length] > 63 ) {
            bonjourName = [bonjourName substringToIndex:62];
        }
        NSCharacterSet *charactersToRemove = [[NSCharacterSet characterSetWithRange:NSMakeRange(32,126)]invertedSet];
        bonjourName = [[bonjourName componentsSeparatedByCharactersInSet:charactersToRemove] componentsJoinedByString:@""];
        const char* cstr = [bonjourName cStringUsingEncoding:NSUTF8StringEncoding];
        strcpy((char*) &replymessage[44], cstr);//long name 44 + 64 + 64 of node report = 172
		
		replymessage[173] = 2;      // max 4 ports [172] hibyte == 0
        
        int capabilities = 5;       //port is Art-Net bytes 0-5 0b000101 dmx is 0b000000
        if ((( config.inprotocol == 0 ) || (config.inprotocol == 1 )) && _dmxinputenabled ) {
            capabilities += 128;
        }
        if ((( config.outprotocol == 0 ) || (config.outprotocol == 1 )) && [self isSending] ) {
            capabilities += 64;
        }
		replymessage[174] = capabilities;     //port types[174-177] 5=Art-Net + 128 can output from network (DMX-Import) + 64 can input onto network (DMX-Out)
        replymessage[175] = capabilities;
		
        if ((( config.outprotocol == 0 ) || (config.outprotocol == 1 )) && [self isSending] ) {
            replymessage[178] = 128;	//good input onto net (DMX-Out) 178-181
            if ( _dmxmaxout > DMX_DIMMERS_IN_UNIVERSE ) {
                replymessage[179] = 128;
            }
        }
        
        if ( _dmxinputenabled ) {
            replymessage[182] = 128;	//good output from net (DMX-Import) 182-185
            replymessage[183] = 128;	//good output from net (DMX-Import) 182-185
        }
		
		replymessage[186] =  config.outuniverse + 16*config.outsubnet;  //[186-189]
        replymessage[187] =  config.outuniverse + 1 + 16*config.outsubnet;  //[186-189]
		
		replymessage[190] = config.inuniverse + (config.insubnet << 4);		//[190-193] means DMX out from Art-Net
        replymessage[191] =  replymessage[190] + 1;             //second universe follows first
        
        // 194=swvideo, 195=swMacro 196=swRemote, 197-200 spare 201style 202-207 MAC 208-211 Bind IP 212 status 26x8 = 238 total bytes
		
		NSInteger numbytes;
		[_sthreadLock lock];
		if ((numbytes=sendto(bsock, replymessage, 239, 0,
							 (struct sockaddr *)&reply_addr, (socklen_t)sizeof reply_addr)) == -1) {
			perror("reply sendto");
			[CTStatusReporter reportStatus:[NSString stringWithFormat:@"ArtNet reply sendto error, address %s\n", inet_ntoa(reply_addr.sin_addr)]];
			[self artnetReplyFailure];
		}
		[_sthreadLock unlock];
	}
}

-(void) sendArtAddressCommand:(unsigned char) cb {
    unsigned char replymessage[107];
    int i;
    for ( i=0; i<107; i++) {
        replymessage[i] = 0;
    }
    strcpy((char*)replymessage, "Art-Net");
    replymessage[9] = 0x60; // opcode
    replymessage[11] = 14;  // protocol version
    replymessage[106] = cb;
    NSInteger numbytes;
    
    NSString* unicaststr = config.unicastAddress;
    if ( [unicaststr length] == 0 ) {
        unicaststr = NULL;
    }
    if ( unicaststr ) {
        their_addr.sin_addr.s_addr = inet_addr([unicaststr cStringUsingEncoding:NSASCIIStringEncoding]);
    } else {
        return;     //Do Not Broadcast
    }
    
    if ((numbytes=sendto(_bfd, replymessage, 107, 0,
                         (struct sockaddr *)&their_addr, (socklen_t)(sizeof their_addr))) == -1) {
        [self sendingFailure:[NSString stringWithFormat:@"sending to: %s\nerror: %s\n", inet_ntoa(their_addr.sin_addr), strerror(errno)]];
    }
}

unsigned char replymessage[239];

-(void) broadcastDMX {						//requires dmx be copied to _outmessage and header set prior to calling
	if ( _bfd < 0 ) {
		[self createSendSocket];
	}
	
	if ( _bfd > 0 ) {
		NSInteger numbytes;
		[_sthreadLock lock];
        if ( _zero ) {
            [self writeZeroOutput];
        }
        
        if ( _dmxmaxout > DMX_DIMMERS_IN_UNIVERSE ) {
            //send entire first universe
            int bytes = DMX_DIMMERS_IN_UNIVERSE + [self dmxStartIndexForProtocol:config.outprotocol];
			[self forceUnicastAddressForPage:0];
            [self updateSequenceForPage:0];         // 6-28-15 updated so each packet sent is numbered
            if ((numbytes=sendto(_bfd, _messageout, bytes, 0,
                                 (struct sockaddr *)&their_addr, (socklen_t)(sizeof their_addr))) == -1) {
                [self sendingFailure:[NSString stringWithFormat:@"sending to: %s\nerror: %s\n", inet_ntoa(their_addr.sin_addr), strerror(errno)]];
            }
            //second universe send here
            //bytes = _dmxmaxout - DMX_DIMMERS_IN_UNIVERSE  + [self dmxStartIndexForProtocol:config.outprotocol];
            bytes = DMX_DIMMERS_IN_UNIVERSE  + [self dmxStartIndexForProtocol:config.outprotocol];
			[self forceUnicastAddressForPage:1];
            [self updateSequenceForPage:1];
            if ((numbytes=sendto(_bfd, &_messageout[MESSAGE_OUT_PAGE_SIZE], bytes, 0,
                                 (struct sockaddr *)&their_addr, (socklen_t)(sizeof their_addr))) == -1) {
                [self sendingFailure:[NSString stringWithFormat:@"sending to: %s\nerror: %s\n", inet_ntoa(their_addr.sin_addr), strerror(errno)]];
            }
        } else {
            int bytes = _dmxmaxout + [self dmxStartIndexForProtocol:config.outprotocol];
            [self forceUnicastAddressForPage:0];
            [self updateSequenceForPage:0];
            if ((numbytes=sendto(_bfd, _messageout, bytes, 0,
                                 (struct sockaddr *)&their_addr, (socklen_t)(sizeof their_addr))) == -1) {
                [self sendingFailure:[NSString stringWithFormat:@"sending to: %s\nerror: %s\n", inet_ntoa(their_addr.sin_addr), strerror(errno)]];
            }
        }
        
		[_sthreadLock unlock];
        
        last_send_time = [NSDate timeIntervalSinceReferenceDate];
        
        //  get poll reply on same socket, checking as we send
        //  as of 8-5-15 create broadcast socket assigns port
        if ( config.outprotocol != DMX_TYPE_SACN ) {
            [self readAvailableArtNetPacketsFromBroadcastSocket];
        }
	}
}

#pragma mark buffer writing methods

-(void) prepareForFade {
}

-(void) prepareBufferForWrite {
    if ( ! _zero ) {
        _writing_to_buffer = YES;
    }
}

-(void) writeToBuffer:(unsigned char*) dmxa addresses:(int) sa profiles:(int*) proa {   //baseline write non-combining, zeroing
	if ( _zero ) {
        return;
    }
    int n;
	int offset = [self dmxStartIndexForProtocol:config.outprotocol];	//header is added by [self broadcastDMX];
    int universe;
	
	for (n=0; n<MAX_DIMMERS; n++) {
        universe = (DMX_DIMMERS_IN_UNIVERSE);
        universe = (universe * MESSAGE_OUT_PAGE_SIZE) - (universe * DMX_DIMMERS_IN_UNIVERSE);
		if ( n<sa ) {
            _messageout[offset + n + universe] = dmxa[n];//[LXDimmerProfileManager outputFor:dmxa[n] profile:proa[n]];
		} else {
			_messageout[offset + n + universe] = 0;
		}
	}
	
    //used to be different for Art-Net but results in malformed packets
    //sh0uld be even multiples of universes...

    if ( sa <= DMX_DIMMERS_IN_UNIVERSE ) {
        _dmxmaxout = DMX_DIMMERS_IN_UNIVERSE;
    } else {
        _dmxmaxout = MAX_DIMMERS;
    }
}

-(void) addToBuffer:(unsigned char*) dmxa addresses:(int) sa profiles:(int*) proa { //combines current buffer with dmxa using HTP
	if ( _zero ) {
        return;
    }
    int n;
	int offset = [self dmxStartIndexForProtocol:config.outprotocol];	//header is added by [self broadcastDMX];
	int c = sa;
	unsigned char dn;
	if ( c > MAX_DIMMERS ) {
		c = MAX_DIMMERS;
	}
    int index;
    int universe;
	
	for (n=0; n<c; n++) {
        dn = dmxa[n];//[LXDimmerProfileManager outputFor:dmxa[n] profile:proa[n]];
        universe = (DMX_DIMMERS_IN_UNIVERSE);
        universe = (universe * MESSAGE_OUT_PAGE_SIZE) - (universe * DMX_DIMMERS_IN_UNIVERSE);
        index = offset + n + universe;
		if ( dn > _messageout[index] ) {
			_messageout[index] = dn;
		}
	}
	
	if ( c > _dmxmaxout ) {
		_dmxmaxout = c;
	}
    
    //as of 5-23-14 always send full universe packets if less, you must fill in fields in art-net packet
    //if ( config.outprotocol == DMX_TYPE_SACN ) {
        if ( _dmxmaxout <= DMX_DIMMERS_IN_UNIVERSE ) {
            _dmxmaxout = DMX_DIMMERS_IN_UNIVERSE;
        } else {
            _dmxmaxout = MAX_DIMMERS;
        }
	//}
}


-(void) finishBufferWrite {
    [self addHeaderToDMXMessage];
    
    if ( [self isSending] ) {
        [self broadcastDMX];	//broadcast now!!
        _writing_to_buffer = NO;
        
        if (( config.outprotocol == 1 ) || ( config.outprotocol == 0 )) {
            if ( last_poll_time + 30 < [NSDate timeIntervalSinceReferenceDate] ) {
                if ( ! [self isClosing] && ( _bfd > 0 ) ) {
                    self.listPollResults = NO;
                    [self broadcastArtNetPoll];
                }
            }
        }
    } else {
        _writing_to_buffer = NO;
        if ( ! [self isClosing] ) {     // allows loop to end if closing
            [self startSending];        // will cause broadcast
        }
    }
}

-(void) fadeFinished {
}

-(void) zeroBuffer { //should be called only if sending  (Possibly add stopAll notification)
    _zero = YES;
    [self broadcastDMX];
}

-(void) writeZeroOutput {
    int n;
    int offset = [self dmxStartIndexForProtocol:config.outprotocol];	//header is added by [self broadcastDMX];
    int universe;
    
    for (n=0; n<MAX_DIMMERS; n++) {          //zero both universes
        universe = (DMX_DIMMERS_IN_UNIVERSE);
        universe = (universe * MESSAGE_OUT_PAGE_SIZE) - (universe * DMX_DIMMERS_IN_UNIVERSE);
        _messageout[offset + n + universe] = 0;
    }
    
    if ( _dmxmaxout <= DMX_DIMMERS_IN_UNIVERSE ) {          //pin _dmxmaxout to complete universe(es)
        _dmxmaxout = DMX_DIMMERS_IN_UNIVERSE;
    } else {
        _dmxmaxout = MAX_DIMMERS;
    }
}


#pragma mark end buffer writing methods

+(void) setArtNetStringToBytes:(unsigned char*) c {
    strcpy((char*)c, "Art-Net");    //strcpy adds terminating zero
}

+(int) getDMXEthernetAddrForProtocol:(int) p subnet:(int) s universe:(int) u {
	int a, b, c, d;
	if ( p < DMX_TYPE_SACN ) {
		if ( p == DMX_TYPE_ARTNET10 ) {
			a = intFromHex('0', 'a');
		} else {
			a = intFromHex('0', '2');
		}
		NSString* mac = [LXDMXEthernetInterface getEn0MACstring];
		b = intFromHex([mac characterAtIndex:9], [mac characterAtIndex:10]);
		c = intFromHex([mac characterAtIndex:12], [mac characterAtIndex:13]);
		d = intFromHex([mac characterAtIndex:15], [mac characterAtIndex:16]);
	} else {
		a = 239;
		b = 255;
		c = s & 0xff;
		d = u & 0xff;
	}
	int r = ints2saddr( a, b, c, d );
	return r;
}

+(NSString*) getNetIPStringForProtocol:(int) p subnet:(int) s universe:(int) u {
	int a, b, c, d;
	if ( p < DMX_TYPE_SACN ) {
		if ( p == DMX_TYPE_ARTNET10 ) {
			a = intFromHex('0', 'a');
		} else {
			a = intFromHex('0', '2');
		}
		NSString* mac = [LXDMXEthernetInterface getEn0MACstring];
		b = intFromHex([mac characterAtIndex:9], [mac characterAtIndex:10]);
		c = intFromHex([mac characterAtIndex:12], [mac characterAtIndex:13]);
		d = intFromHex([mac characterAtIndex:15], [mac characterAtIndex:16]);
	} else {
		a = 239;
		b = 255;
		c = s & 0xff;
		d = u & 0xff;
	}
	return [NSString stringWithFormat:@"%i.%i.%i.%i", a, b, c, d];
}

+(NSString*) getEn0MACstring {
	NSMutableArray *args = [NSMutableArray arrayWithObjects:@"en0", nil];
	
	NSTask *task = [[NSTask alloc] init];
	NSPipe *pipe = [NSPipe pipe];
	[task setLaunchPath:@"/sbin/ifconfig"];
	[task setArguments:args];
	[task setStandardOutput:pipe];
	
	[task launch];
	
	while ( [task isRunning] ) {
		[NSThread sleepForTimeInterval:0.5];
	}
	
	NSString* outstr = [[NSString alloc] initWithData:[[pipe fileHandleForReading] readDataToEndOfFile]encoding:NSUTF8StringEncoding];
	NSString* macstr = substringBeforeSeperator(substringAfterSeperator(outstr, @"ether "), @"\n");
	return macstr;
}

+(NSArray*) UUIDArray {
	NSMutableArray* ra;
	ra = [[NSUserDefaults standardUserDefaults] objectForKey:SACN_CID_UUID];
	if ( ! ra) {
		ra = [[NSMutableArray alloc] initWithCapacity:16];
		CFUUIDRef uuid = CFUUIDCreate ( NULL );
		CFUUIDBytes ubyte = CFUUIDGetUUIDBytes ( uuid );
		[ra addObject:[NSNumber numberWithInt:ubyte.byte0]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte1]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte2]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte3]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte4]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte5]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte6]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte7]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte8]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte9]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte10]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte11]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte12]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte13]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte14]];
		[ra addObject:[NSNumber numberWithInt:ubyte.byte15]];
		CFRelease(uuid);
		[[NSUserDefaults standardUserDefaults] setObject:ra forKey:SACN_CID_UUID];
	}
	return ra;
}

@end
