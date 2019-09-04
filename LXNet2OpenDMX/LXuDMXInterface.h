//
//  LXuDMXInterface.h
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 9/3/19.
//  Copyright © 2019 Claude Heintz. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "usb.h"    /* this is libusb, see http://libusb.sourceforge.net/ */
#include "LXDMXCommonInclude.h"

NS_ASSUME_NONNULL_BEGIN

@interface LXuDMXInterface : NSObject {
    /*
     * handle to usb device
     */
    usb_dev_handle* handle;
    
    /*
     * flag, YES if libusb usb_init() has been called.
     */
    BOOL _usb_init_called;
    
    /*
     *  Array of DMX Level data including the start code
     */
    uint8_t _dmxdata[DMX_SLOTS_PLUS_START];
    
    /*
     *  Universe is used to check LXDMX_RECEIVE_NOTIFICATION notifications before copying data
     *  from the LXDMXReceivedMessage.
     */
    NSInteger universe;
}

-(id) init;
-(void) dealloc;

-(void) startDevice;
-(void) closeDevice;
-(void) DMXReceived:(NSNotification*) note;

@end

NS_ASSUME_NONNULL_END


#define UDMX_STATUS_UPDATE_NOTIFICATION @"UDMX_STATUS_UPDATE_NOTIF"

#define LXuDMX_STATE_OFF     0
#define LXuDMX_STATE_RED     1
#define LXuDMX_STATE_GREEN   2
#define LXuDMX_STATE_BLUE    3
#define LXuDMX_STATE_YELLOW  4
#define LXuDMX_STATE_ORANGE  5

