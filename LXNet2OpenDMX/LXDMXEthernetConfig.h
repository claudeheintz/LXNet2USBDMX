//
//  LXDMXEthernetConfig.h
//  LXNet2OpenDMX
//
//  Created by Claude Heintz on 6/28/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <netinet/in.h>

@interface LXDMXEthernetConfig : NSObject {
    int insubnet;
    int inuniverse;
    int inprotocol;
    int outsubnet;
    int outuniverse;
    int outprotocol;
    
    NSInteger acnPriority;
    
    BOOL unicast;
    BOOL setUnicastFromReply;
    BOOL useAnyInADDR;
    
    NSString* artnetBindAddress;
    NSString* sacnBindAddress;
    NSString* unicastAddress;
    
    NSString* shortName;
}

@property (assign) int insubnet;
@property (assign) int inuniverse;
@property (assign) int inprotocol;
@property (assign) int outsubnet;
@property (assign) int outuniverse;
@property (assign) int outprotocol;

@property (assign) NSInteger acnPriority;

@property (assign) BOOL unicast;
@property (assign) BOOL setUnicastFromReply;
@property (assign) BOOL useAnyInADDR;

@property (retain) NSString* artnetBindAddress;
@property (retain) NSString* sacnBindAddress;
@property (retain) NSString* unicastAddress;

@property (retain) NSString* shortName;

-(id) init;
+(LXDMXEthernetConfig*) dmxEthernetConfig;

-(in_addr_t) bindAddressForArtNet;
-(in_addr_t) bindAddressForSACN;

@end
