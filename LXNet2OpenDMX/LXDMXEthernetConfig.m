//
//  LXDMXEthernetConfig.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/28/16.
//  Copyright © 2016-2019 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "LXDMXEthernetConfig.h"
#include <arpa/inet.h>

@implementation LXDMXEthernetConfig

@synthesize insubnet;
@synthesize inuniverse;
@synthesize inprotocol;
@synthesize outsubnet;
@synthesize outuniverse;
@synthesize outprotocol;
@synthesize acnPriority;
@synthesize unicast;
@synthesize setUnicastFromReply;
@synthesize useAnyInADDR;
@synthesize artnetBindAddress;
@synthesize sacnBindAddress;
@synthesize unicastAddress;
@synthesize shortName;

-(id) init {
    self = [super init];
    
    if ( self ) {
        self.insubnet = 0;
        self.inuniverse = 0;
        self.inprotocol = 0;
        self.outsubnet = 0;
        self.outuniverse = 0;
        self.outprotocol = 0;
        self.acnPriority = 100;
        
        self.unicast = NO;
        self.setUnicastFromReply = YES;
        self.useAnyInADDR = YES;
        
        self.shortName = @"LXDMXEthernet";
    }
    
    return self;
}

+(LXDMXEthernetConfig*) dmxEthernetConfig {
    return [[LXDMXEthernetConfig alloc] init];
}

-(in_addr_t) bindAddressForArtNet {
    if ( ! self.useAnyInADDR ) {
        if ( artnetBindAddress ) {
            if ( [artnetBindAddress length] > 0 ) {
                return inet_addr([artnetBindAddress cStringUsingEncoding:NSASCIIStringEncoding]);
            }
        }
    }
    return INADDR_ANY;
}

-(in_addr_t) bindAddressForSACN {
    if ( ! self.useAnyInADDR ) {
        if ( sacnBindAddress ) {
            if ( [sacnBindAddress length] > 0 ) {
                return inet_addr([sacnBindAddress cStringUsingEncoding:NSASCIIStringEncoding]);
            }
        }
    }
    return INADDR_ANY;
}

@end
