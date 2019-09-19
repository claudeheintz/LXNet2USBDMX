//
//  LXuDMXInterface.h
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 9/3/19.
//  Copyright © 2019 Claude Heintz. All rights reserved.
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


#define LXUSBDMX_LIBUSB_DRIVER_PATH @"/usr/local/lib/libusb.dylib"
