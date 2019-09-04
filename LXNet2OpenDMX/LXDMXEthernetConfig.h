//
//  LXDMXEthernetConfig.h
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/28/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
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
