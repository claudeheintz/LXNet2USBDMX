//
//  LXOpenDMXInterface.h
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/23/16.
//
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
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <time.h>
#include "ftd2xx.h"
#include "string.h"
#include "unistd.h"
#include <stdint.h>
#include "LXDMXCommonInclude.h"

@interface LXOpenDMXInterface : NSObject  {
    /*
     *  Handle for FT D2XX device
     */
    FT_HANDLE device_handle;
    /*
     *  Array of DMX Level data including the start code
     */
    uint8_t _dmxdata[DMX_SLOTS_PLUS_START];
    /*
     *  Sending flag is used to control sending loop.
     *  Set to YES when before startSending starts sending thread.
     *  Set to NO by stopSending ends while loop in sendDMX thread.
     */
    BOOL sending;
    /*
     *  Active flag indicates sending thread is running.
     */
    BOOL active;
    /*
     *  Universe is used to check LXDMX_RECEIVE_NOTIFICATION notifications before copying data
     *  from the LXDMXReceivedMessage.
     */
    NSInteger universe;
    
    NSTimeInterval frameTime1, frameTime2;
}

/*
 * initialize LXNet2OpenDMX object with start code and dmx levels set to zero
 */
-(id) init;

/*
 *  openConnection opens a D2XX serial connection to the first D2XX device found
 *  and stores a handle to that device in device_handle.
 */
-(BOOL) openConnection;
/*
 *  setupCommParameters sets the baud rate, data characteristics and flow control of the D2XX device referred to by device_handle
 */
-(BOOL) setupCommParameters;
/*
 *  ftErrorString provides a readable string from an FT_STATUS code
 */
-(NSString*) ftErrorString:(int) code;

/*
 *  statusChange posts a notification of the status of the device connection by calling postStatusChange
 *  on the main thread.
 */
-(void) statusChange:(NSUInteger) status;
/*
 *  postStatusChange does the actual posting of a status change notification.
 *  Assuming this will cause a UI update, postStatusChange should only be called on the main thread.
 */
-(void) postStatusChange:(NSNumber*) change;

/*
 *  startSending opens a connection to a D2XX device and initializes its comm settings.
 *  It then detaches a thread with the sendDMX method which will loop and write to the serial device.
 */
-(void) startSending;
/*
 *  stopSending sets the sending flag to NO and waits for thread to exit (ie active == NO)
 */
-(void) stopSending;
/*
 * isSending indicates if the sending thread is looping, sending DMX
 */
-(BOOL) isSending;
/*
 *  checkSendingError does nothing if s == FT_OK.
 *  In the case of an error, checkSendingError closes the connection and sends a status notification.
 *  checkSendingError returns the sending flag (YES if the sendDMX loop should continue).
 */
-(BOOL) checkSendingError:(FT_STATUS) s;
/*
 *  sendDMX is the method used by the sending thread to continuously send DMX using the FT D2XX serial connection
 */
-(void) sendDMX;


/*
 *  DMXReceived is called as the result of a LXDMX_RECEIVE_NOTIFICATION
 *  The object of the notificaton is an LXDMXReceivedMessage object.
 *  If the LXDMXReceivedMessage's universe matches this object's universe,
 *  levels are copied from the LXDMXReceivedMessage into this object's _dmxData.
 *  Copying _dmxData is synchronized so it does not happen simultaneously with
 *  FT_Write in the sendDMX loop.
 */
-(void) DMXReceived:(NSNotification*) note;

@end

#define DMX_BREAK_USEC 100
#define DMX_MAB_USEC 12
#define DMX_PACKET_USEC 23000

#define LXOPENDMX_STATUS_CHANGE_NOTIFICATION @"lxopendmx_status_change"

#define LXUSBDMX_FTDID2XX_DRIVER_PATH @"/usr/local/lib/libftd2xx.1.4.16.dylib"
