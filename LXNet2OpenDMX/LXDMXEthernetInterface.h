//
//  LXDMXEthernetInterface.h
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 12/3/09.
//  Copyright 2009-2016 Claude Heintz Design. All rights reserved.
//
/*
 See https://www.claudeheintzdesign.com/lx/opensource.html
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 * Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 * Neither the name of LXNet2USBDMX nor the names of its
 contributors may be used to endorse or promote products derived from
 this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 -----------------------------------------------------------------------------------
 */

#import <Cocoa/Cocoa.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include "LXDMXCommonInclude.h"

@class LXDMXReceivedMessage;
@class LXDMXEthernetConfig;

#define MESSAGE_IN_BUFFER_SIZE 1024
#define MESSAGE_OUT_PAGE_SIZE 638
#define MESSAGE_OUT_BUFFER_SIZE 1276

#define SACN_PORT 5568
#define ARTNET_PORT 6454

#define ARTNET_ARTDMX 0x5000
#define ARTNET_ARTPOLL 0x2000
#define ARTNET_ARTPOLL_REPLY 0x2100
#define ARTNET_ARTADDRESS 0x6000
#define ARTNET_ARTDMX_DATA_INDEX 18
#define SACN_DMX_START_CODE_INDEX 125
#define SACN_DMX_DATA_INDEX 126
#define SACN_CID_UUID @"e131_uuid"

#define MAX_DIMMERS 512

#define DMX_TYPE_USB -1
#define DMX_TYPE_ARTNET2 0
#define DMX_TYPE_ARTNET10 1
#define DMX_TYPE_SACN 2

#define LXDMX_ETHERNET_CONFIG_CHANGE @"LXDMXEthernetConfigChanged"

@interface LXDMXEthernetInterface : NSObject {
    LXDMXEthernetConfig* config;
	int _receiveduniverse;
    int _receiveduniverse2;
	
	unsigned char listen_netaddr[4];
	struct sockaddr_in _clientAddress;
    socklen_t fromlen;
	struct sockaddr_in their_addr; // connector's address information
	struct sockaddr_in send_addr; // connector's address information
    struct sockaddr_in recv_addr;


	unsigned char _messagein[MESSAGE_IN_BUFFER_SIZE];	//message buffer
	unsigned char _prmessage[MESSAGE_IN_BUFFER_SIZE];	//message buffer
	int _messagelength;
    /*
     *  message out accomodates 2 outgoing messages
     */
	unsigned char _messageout[MESSAGE_OUT_BUFFER_SIZE];			//dmx buffer  512 + max Header = 638 for 1 universe
	int _dmxmaxin;						//number of addresses universe 0
    int _dmxmaxin2;						//number of addresses universe 1
	int _dmxmaxout;
	int _sequence;
	
	int _lfd;
	int _bfd;
	BOOL _listening;
	BOOL _sending;
    BOOL _closing;
    BOOL _creating_socket;
    BOOL _zero;
	BOOL _dmxinputenabled;
    BOOL _local_listenenabled;
	BOOL _readpending;
	BOOL _readdirty;
    BOOL _readpendingU2;
	BOOL _readdirtyU2;
    BOOL _suspend_send_error;
    LXDMXReceivedMessage* _currentReceivedMessage;
    LXDMXReceivedMessage* _pendingReceivedMessage;
    LXDMXReceivedMessage* _currentReceivedMessageU2;
    LXDMXReceivedMessage* _pendingReceivedMessageU2;
	
	BOOL _writing_to_buffer;
	
	NSThread* _listenthread;
	NSThread* _sendthread;
	NSLock* _sthreadLock;
	
    NSString* _defaultBroadcast;
	
	double last_poll_time;
    double last_send_time;
    
    BOOL listPollResults;
}

@property (assign) BOOL listPollResults;
@property (retain) LXDMXEthernetConfig* config;

-(id) initWithConfig:(LXDMXEthernetConfig*) econfig;
+(LXDMXEthernetInterface*) sharedDMXEthernetInterface;
+(void) initSharedInterfaceWithConfig:(LXDMXEthernetConfig*) econfig;
+(void) closeSharedDMXEthernetInterface;
+(void) shutdownSharedDMXEthernetInterface;
+(void) closeSharedDMXEthernetInterfaceForReset;

-(unsigned char*) DMXArrayForRead; //for input
-(int) dmxArraySize;
-(int) dmxStartIndexForProtocol:(int) p;
-(void) addHeaderToDMXMessageForPage:(int) page;
-(void) addHeaderToDMXMessage;
-(int) packetSequenceNumber;
-(void) validateSACNPriority;
-(void) forceUnicastAddressForPage:(int) page;

-(int) receivedUniverse;
-(void) setEnableDMXIn:(BOOL) rx;
-(void) setEnableLocalListen:(BOOL) b;
-(void) setReceiveTwoUniverses:(BOOL) twou;

-(void) postDMXEthernetConfigChanged;
-(void) configChanged;
-(void) setInputUniverseAddress:(unsigned char) u;
-(void) setInputSubnetAddress:(unsigned char) s;
-(void) setInputNetAddress:(unsigned char) s;

-(int) createAndBindSocketForProtocol:(int) protocol;
-(int) createAndBindBroadcastSocket;

-(int) createListenSocket;
-(void) closeListenSocket;
-(void) createSendSocket;
-(void) closeSendSocket;

-(int) listenfd;
-(void) setListenFD:(int) fd;
-(int) connectionSetForRead:(int) fdescriptor  create:(BOOL) create;

-(void) findDefaultBroadcastAddressIfNeeded;
-(void) findDefaultBroadcastAddress;
-(NSString*) defaultBroadcastAddress;
+(NSString*) findIPInterfaceFor:(NSString*) astr;
+(NSString*) findNonLocalAddressWithPrefix:(NSString*) astr orAddress:(NSString*) paddress;
+(BOOL) hostHasAddress:(NSString*) taddr;

-(NSThread*) listeningThread;
-(void) setListeningThread:(NSThread*) thread;
-(BOOL) isListening;
-(void) setListening:(BOOL) l;
-(void) startListening;
-(void) stopListening;
-(void)listen:(id) anObject;
-(void) readAMessage;

- (void) readAvailableArtNetPacketsFromBroadcastSocket;

-(void) receivedArtNetMessage:(unsigned char*) mbytes length:(int) mlength readDMX:(BOOL) readOK;
-(void) receivedDMXOverEthernetMessage;
-(LXDMXReceivedMessage*) currentDMXReceivedMessage;
-(void) setCurrentDMXReceivedMessage:(LXDMXReceivedMessage*) crm;
-(LXDMXReceivedMessage*) currentDMXReceivedMessageU2;
-(void) setCurrentDMXReceivedMessageU2:(LXDMXReceivedMessage*) crm;
-(void) readToCurrentDMXReceivedMessage:(unsigned char*) msg;
-(void) readToCurrentDMXReceivedMessageU2:(unsigned char*) msg;
-(LXDMXReceivedMessage*) pendingDMXReceivedMessage;
-(void) setPendingDMXReceivedMessage:(LXDMXReceivedMessage*) crm;
-(LXDMXReceivedMessage*) pendingDMXReceivedMessageU2;
-(void) setPendingDMXReceivedMessageU2:(LXDMXReceivedMessage*) crm;
-(void) readToPendingDMXReceivedMessage:(unsigned char*) msg;
-(void) readToPendingDMXReceivedMessageU2:(unsigned char*) msg;
-(void) postDMXMessageReceived;
-(void) postDMXMessageReceivedU2;
-(void) printMessage:(unsigned char*)mbytes  length:(int) mlength;

-(void) postCurrentDMXReceivedMessageU2;

-(NSThread*) sendingThread;
-(void) setSendingThread:(NSThread*) thread;
-(BOOL) isSending;
-(void) setSending:(BOOL) s;
-(BOOL) isClosing;
-(void) setClosing:(BOOL) s;
-(void) startSending;
-(void) stopSending;
- (void)send:(id) anObject;
-(void) setSuspendSendingErrorReporting:(BOOL) suspend;
-(void) sendingFailure:(NSString*) message;
-(void) artnetReplyFailure;

-(void) broadcastArtNetPoll;
-(void) sendArtNetReply;
-(void) sendArtAddressCommand:(unsigned char) cb;
-(void) broadcastDMX;

-(void) prepareForFade;
-(void) prepareBufferForWrite;
-(void) writeToBuffer:(unsigned char*) dmxa addresses:(int) sa profiles:(int*) proa;
-(void) addToBuffer:(unsigned char*) dmxa addresses:(int) sa profiles:(int*) proa;
-(void) finishBufferWrite;
-(void) fadeFinished;

+(void) setArtNetStringToBytes:(unsigned char*) c;
+(NSString*) getNetIPStringForProtocol:(int) p subnet:(int) s universe:(int) u;
+(int) getDMXEthernetAddrForProtocol:(int) p subnet:(int) s universe:(int) u;
+(NSString*) getEn0MACstring;
+(NSArray*) UUIDArray;

@end
