//
//  AppDelegate.h
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/24/16.
//  Copyright © 2016-2019 Claude Heintz. All rights reserved.
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
#import "LXOpenDMXInterface.h"
#import "LXuDMXInterface.h"

@class CTrgbLedView;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    LXOpenDMXInterface* openDMXInterface;
    LXuDMXInterface* uDMXInterface;
    IBOutlet NSButton* dmxbutton;
    IBOutlet NSButton* udmxbutton;
    IBOutlet NSButton* netbutton;
    IBOutlet NSMatrix* protocolMatrix;
    IBOutlet NSTextField* statusField;
    IBOutlet CTrgbLedView* netStatus;
    IBOutlet CTrgbLedView* dmxStatus;
    IBOutlet CTrgbLedView* udmxStatus;
    NSTimeInterval dmxtime;
    NSString* appStatus;
}

@property (retain) NSString* appStatus;

-(void) initDefaults;

-(void) udmxStatusUpdate:(NSNotification*) note;
-(void) appStatusUpdate:(NSNotification*) note;
-(void) openDMXStatusUpdate:(NSNotification*) note;
-(void) DMXReceived:(NSNotification*) note;
-(void) dmxEthernetConfigChanged:(NSNotification*) note;
-(void) windowWillClose:(NSNotification *)window;

-(IBAction) toggleDMX:(id) sender;
-(IBAction) toggleUDMX:(id) sender;
-(IBAction) toggleEthernet:(id) sender;
-(IBAction) protocolMatrixChanged:(id) sender;

@end

