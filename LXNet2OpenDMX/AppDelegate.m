//
//  AppDelegate.m
//  LXNet2OpenDMX
//
//  Created by Claude Heintz on 6/24/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "AppDelegate.h"
#import "LXDMXEthernetInterface.h"
#import "LXDMXEthernetConfig.h"
#import "LXOpenDMXInterface.h"
#import "LXuDMXInterface.h"
#import "LXDMXCommonInclude.h"
#import "CTStatusReporter.h"
#import "CTrgbLedView.h"
#include <sys/time.h>



@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

@synthesize appStatus;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    openDMXInterface = NULL;
    uDMXInterface = NULL;
    
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(appStatusUpdate:)
                                                 name: CTSTATUS_UPDATE_NOTIFICATION
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(udmxStatusUpdate:)
                                                 name: UDMX_STATUS_UPDATE_NOTIFICATION
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(openDMXStatusUpdate:)
                                                 name: LXOPENDMX_STATUS_CHANGE_NOTIFICATION
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(DMXReceived:)
                                                 name: LXDMX_RECEIVE_NOTIFICATION
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(dmxEthernetConfigChanged:)
                                                 name: LXDMX_ETHERNET_CONFIG_CHANGE
                                               object:nil];
    dmxtime = [NSDate timeIntervalSinceReferenceDate];
    
    NSString* statusString = @"";
    
    if ( ! [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/local/lib/libftd2xx.1.4.16.dylib"] ) {
        [dmxbutton setEnabled:NO];
        statusString = @"Missing d2xx. ";
    }
    if ( ! [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/local/lib/libusb-0.1.4.dylib"] ) {
        [dmxbutton setEnabled:NO];
        statusString = [NSString stringWithFormat:@"%@Missing libusb.", statusString];
    }
    
    [statusField setStringValue:statusString];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:openDMXInterface];
    
    if ( [LXDMXEthernetInterface sharedDMXEthernetInterface] ) {
        [[LXDMXEthernetInterface sharedDMXEthernetInterface] setEnableDMXIn:NO];
        [LXDMXEthernetInterface closeSharedDMXEthernetInterface];
    }
    
    if ( openDMXInterface ) {
        [self toggleDMX:self];  // stops sending & releases interface
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma preferences

-(void) initDefaults {
    NSUserDefaults * prefs  = [NSUserDefaults standardUserDefaults];
    
    NSString* pathToDefaultDefaults = [[NSBundle mainBundle] pathForResource:@"user_defaults" ofType:@"plist"];
    NSMutableDictionary * defaultPrefs = [NSMutableDictionary dictionaryWithContentsOfFile: pathToDefaultDefaults];
    [prefs registerDefaults: defaultPrefs];
}

#pragma mark notifications

-(void) appStatusUpdate:(NSNotification*) note {
    CTStatusReporter* sr = [note object];
    if ( [sr checkAndAlertUser] ) {
        if ( appStatus ) {
            [statusField setStringValue:appStatus];
            self.appStatus = NULL;
        }
    } else {
        if (sr.level == CT_STATUS_LEVEL_NOLOG_GREEN ) {
            [statusField setStringValue:sr.status];
        } else {
            self.appStatus = sr.status;
        }
    }
}

-(void) udmxStatusUpdate:(NSNotification*) note {
    NSUInteger status = [[note object] integerValue];
    
    switch (status) {
        case LXuDMX_STATE_GREEN:
            if ( udmxStatus.ledstate != LXuDMX_STATE_GREEN ) {
                udmxStatus.ledstate = LXuDMX_STATE_GREEN;
                [statusField setStringValue:@""];
            }
            break;
        case LXuDMX_STATE_RED:
            [statusField setStringValue:@"Could not find device."];
            udmxStatus.ledstate = LXuDMX_STATE_RED;
            break;
        case LXuDMX_STATE_YELLOW:
            [statusField setStringValue:@"usb_control_msg error."];
            udmxStatus.ledstate = LXuDMX_STATE_YELLOW;
            break;
        case LXuDMX_STATE_BLUE:
            [statusField setStringValue:@"Device ready."];
            udmxStatus.ledstate = LXuDMX_STATE_BLUE;
            break;
            
        default:
            break;
    }
}

-(void) openDMXStatusUpdate:(NSNotification*) note {
    dmxStatus.ledstate =[[note object] integerValue];
    if ( [openDMXInterface isSending] ) {
        [dmxbutton setTitle:@"Stop OpenDMX"];
    } else {
        [dmxbutton setTitle:@"Start OpenDMX"];
    }
}

-(void) DMXReceived:(NSNotification*) note {
    if ( [NSDate timeIntervalSinceReferenceDate] > dmxtime ) {
        if ( netStatus.ledstate == 2 ) {
            netStatus.ledstate = 3;
        } else {
            netStatus.ledstate = 2;
        }
        
        dmxtime = [NSDate timeIntervalSinceReferenceDate] + 1;
    }
}

-(void) dmxEthernetConfigChanged:(NSNotification*) note {
    LXDMXEthernetConfig* config = [note object];
    NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
    [prefs setInteger:config.inuniverse forKey:LXDMX_IN_UNIVERSE];
    [prefs setInteger:config.insubnet forKey:LXDMX_IN_SUBNET];
    [prefs setObject:config.unicastAddress forKey:LXDMX_ETHERNET_UNICAST_ADDRESS];
}

-(void) windowWillClose:(NSNotification *)window {
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

#pragma mark actions

-(IBAction)  toggleDMX:(id) sender {
    if ( openDMXInterface == NULL ) {
        openDMXInterface = [[LXOpenDMXInterface alloc] init];
        [openDMXInterface startSending];
    } else {
        if ( [openDMXInterface isSending] ) {   // STOP
            [openDMXInterface stopSending];
        }
        while ( [openDMXInterface isSending] ) {
            [NSThread sleepForTimeInterval:0.5];
        }
        openDMXInterface = NULL;
    }
}

-(IBAction) toggleUDMX:(id) sender {
    if ( uDMXInterface == NULL ) {
        uDMXInterface = [[LXuDMXInterface alloc] init];
        [uDMXInterface startDevice];
        [udmxbutton setTitle:@"Stop µDMX"];
    } else {
        uDMXInterface = NULL;
        [udmxbutton setTitle:@"Start µDMX"];
        udmxStatus.ledstate = LXuDMX_STATE_OFF;
    }
}

-(IBAction) toggleEthernet:(id) sender  {
    if ( [LXDMXEthernetInterface sharedDMXEthernetInterface] ) {
        [[LXDMXEthernetInterface sharedDMXEthernetInterface] setEnableDMXIn:NO];
        [LXDMXEthernetInterface closeSharedDMXEthernetInterface];
        [netbutton setTitle:@"Start Art-Net"];
        netStatus.ledstate = CTRGB_LED_STATE_OFF;
        [statusField setStringValue:@"Art-Net socket closed"];
    } else {
        LXDMXEthernetConfig* config = [LXDMXEthernetConfig dmxEthernetConfig];
        config.inprotocol = (int)[[NSUserDefaults standardUserDefaults] integerForKey:LXDMX_IN_PROTOCOL];
        if ( config.inprotocol == DMX_TYPE_SACN ) {
            config.inuniverse = 1;
            [protocolMatrix selectCellAtRow:0 column:1];
        } else {
            config.inuniverse = 0;
            [protocolMatrix selectCellAtRow:0 column:0];
        }
        config.insubnet = 0;
        
        config.outprotocol = -1;
        config.outsubnet = 0;
        config.outuniverse = 0;
        config.shortName = @"LXNet2USBDMX";
        [LXDMXEthernetInterface initSharedInterfaceWithConfig:config];
        [[LXDMXEthernetInterface sharedDMXEthernetInterface] setEnableDMXIn:YES];
        [netbutton setTitle:@"Stop Art-Net"];
    }
}

-(IBAction) protocolMatrixChanged:(id) sender  {
    if ( [protocolMatrix selectedColumn] == 0 ) {
        [[NSUserDefaults standardUserDefaults] setInteger:DMX_TYPE_ARTNET10 forKey:LXDMX_IN_PROTOCOL];
    } else {
        [[NSUserDefaults standardUserDefaults] setInteger:DMX_TYPE_SACN forKey:LXDMX_IN_PROTOCOL];
    }
    if ( [LXDMXEthernetInterface sharedDMXEthernetInterface] ) {
        [LXDMXEthernetInterface closeSharedDMXEthernetInterfaceForReset];
        [self toggleEthernet:self];
    }
}

@end
