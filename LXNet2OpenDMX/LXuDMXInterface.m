//
//  LXuDMXInterface.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 9/3/19.
//  Copyright © 2019 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "LXuDMXInterface.h"
#import "LXDMXReceivedMessage.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define USBDEV_SHARED_VENDOR    0x16C0  /* VOTI */
#define USBDEV_SHARED_PRODUCT   0x05E4  /* Obdev's free shared PID */
/* Use obdev's generic shared VID/PID pair and follow the rules outlined
 * in firmware/usbdrv/USBID-License.txt.
 */

#include "uDMX_cmds.h"

static int  usbGetStringAscii(usb_dev_handle *dev, int index, int langid, char *buf, int buflen)
{
    char    buffer[256];
    int     rval, i;
    
    if((rval = usb_control_msg(dev, USB_ENDPOINT_IN, USB_REQ_GET_DESCRIPTOR, (USB_DT_STRING << 8) + index, langid, buffer, sizeof(buffer), 1000)) < 0)
        return rval;
    if(buffer[1] != USB_DT_STRING)
        return 0;
    if((unsigned char)buffer[0] < rval)
        rval = (unsigned char)buffer[0];
    rval /= 2;
    /* lossy conversion to ISO Latin1 */
    for(i=1;i<rval;i++){
        if(i > buflen)  /* destination buffer overflow */
            break;
        buf[i-1] = buffer[2 * i];
        if(buffer[2 * i + 1] != 0)  /* outside of ISO Latin1 range */
            buf[i-1] = '?';
    }
    buf[i-1] = 0;
    return i-1;
}

static usb_dev_handle   *findDevice(void)
{
    struct usb_bus      *bus;
    struct usb_device   *dev;
    usb_dev_handle      *handle = 0;
    
    usb_find_busses();
    usb_find_devices();
    for(bus=usb_busses; bus; bus=bus->next){
        for(dev=bus->devices; dev; dev=dev->next){
            if(dev->descriptor.idVendor == USBDEV_SHARED_VENDOR && dev->descriptor.idProduct == USBDEV_SHARED_PRODUCT){
                char    string[256];
                int     len;
                handle = usb_open(dev); /* we need to open the device in order to query strings */
                if(!handle){
                    fprintf(stderr, "Warning: cannot open USB device: %s\n", usb_strerror());
                    continue;
                }
                /* now find out whether the device actually is obdev's Remote Sensor: */
                len = usbGetStringAscii(handle, dev->descriptor.iManufacturer, 0x0409, string, sizeof(string));
                if(len < 0){
                    fprintf(stderr, "warning: cannot query manufacturer for device: %s\n", usb_strerror());
                    goto skipDevice;
                }
                /* fprintf(stderr, "seen device from vendor ->%s<-\n", string); */
                if(strcmp(string, "www.anyma.ch") != 0)
                    goto skipDevice;
                len = usbGetStringAscii(handle, dev->descriptor.iProduct, 0x0409, string, sizeof(string));
                if(len < 0){
                    fprintf(stderr, "warning: cannot query product for device: %s\n", usb_strerror());
                    goto skipDevice;
                }
                /* fprintf(stderr, "seen product ->%s<-\n", string); */
                if(strcmp(string, "uDMX") == 0)
                    break;
            skipDevice:
                usb_close(handle);
                handle = NULL;
            }
        }
        if(handle)
            break;
    }
    if(!handle)
        NSLog(@"Could not find USB device www.anyma.ch/uDMX");
    return handle;
}

@implementation LXuDMXInterface

-(id) init {
    self = [super init];
    
    if ( self ) {
        handle = NULL;
        _usb_init_called = NO;
        usb_set_debug(0);
        
        universe = 0;                                    // hard coded universe!
    }
    
    return self;
}

-(void) dealloc {
    [self closeDevice];
}

-(void) startDevice {
    if ( ! _usb_init_called ) {
        usb_init();
        _usb_init_called = YES;
    }
    
    if ( handle == NULL ) {
        if((handle = findDevice()) == NULL) {
            [self statusChange:LXuDMX_STATE_RED];
            NSLog(@"Could not find USB device \"uDMX\" with vid=0x%x pid=0x%x\n", USBDEV_SHARED_VENDOR, USBDEV_SHARED_PRODUCT);
        }
    }
    
    if ( handle ) {
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(DMXReceived:)
                                                     name: LXDMX_RECEIVE_NOTIFICATION
                                                   object: nil];
        NSLog(@"Found µDMX device");
        [self statusChange:LXuDMX_STATE_BLUE];
    } else {
        [self statusChange:LXuDMX_STATE_RED];
    }
}

-(void) closeDevice {
    //stop listening for dmx received notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if ( handle != NULL ) {
        usb_close(handle);
        handle = NULL;
    }
}

-(void) DMXReceived:(NSNotification*) note {
    if ( [[note object] receivedUniverse] == universe ) {
        uint8_t* idmx = [[note object] DMXArrayForRead];
        @synchronized(self) {
            for ( int i=0; i<DMX_DIMMERS_IN_UNIVERSE; i++ ) {
                _dmxdata[i] = idmx[i];
            }
        }
        
        int channel = 0;
        
        int nBytes = usb_control_msg(handle, USB_TYPE_VENDOR | USB_RECIP_DEVICE | USB_ENDPOINT_OUT,
                                 cmd_SetChannelRange, 512, channel, (char*)_dmxdata, 512, 5000);
        if (nBytes < 0) {
            NSLog(@"USB error: %s\n", usb_strerror());
            [self statusChange:LXuDMX_STATE_YELLOW];
        } else {
            [self statusChange:LXuDMX_STATE_GREEN];
        }
    }
}


-(void) statusChange:(NSUInteger) status {
    [self performSelectorOnMainThread:@selector(postStatusChange:) withObject:[NSNumber numberWithInteger:status] waitUntilDone:NO];
}

-(void) postStatusChange:(NSNumber*) change {
    [[NSNotificationCenter defaultCenter] postNotificationName:UDMX_STATUS_UPDATE_NOTIFICATION object:change];
}

@end
