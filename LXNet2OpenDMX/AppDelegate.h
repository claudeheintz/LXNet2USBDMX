//
//  AppDelegate.h
//  LXNet2OpenDMX
//
//  Created by Claude Heintz on 6/24/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//

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

