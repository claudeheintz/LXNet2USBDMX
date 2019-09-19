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
#include <dlfcn.h>

#define USBDEV_SHARED_VENDOR    0x16C0  /* VOTI */
#define USBDEV_SHARED_PRODUCT   0x05E4  /* Obdev's free shared PID */
/* Use obdev's generic shared VID/PID pair and follow the rules outlined
 * in firmware/usbdrv/USBID-License.txt.
 */

#include "uDMX_cmds.h"

/*
 *  dynamic library handle for resolving symbols
 */
void* _libusb_dylibHandle = NULL;


// Utility for status reporting

#define CT_STATUS_LEVEL_RED 4

void reportStatus( NSString* msg, int code ) {
    fprintf(stderr, "%s", [msg UTF8String]);
}

static int  usbGetStringAscii(usb_dev_handle *dev, int index, int langid, char *buf, int buflen)
{
    char    buffer[256];
    int     rval, i;
    if ( _libusb_dylibHandle != NULL ) {
        
        int (*usbCtrlMsg) (usb_dev_handle *dev, int requesttype, int request,
                           int value, int index, char *bytes, int size, int timeout);
        usbCtrlMsg =  dlsym(_libusb_dylibHandle, "usb_control_msg");
        
        if((rval = (*usbCtrlMsg)(dev, USB_ENDPOINT_IN, USB_REQ_GET_DESCRIPTOR, (USB_DT_STRING << 8) + index, langid, buffer, sizeof(buffer), 1000)) < 0)
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
        
    } else {    // can't resolve symbol through dylib
        i=1;
    }
    return i-1;
}

static usb_dev_handle   *findDevice(void)
{
    struct usb_bus      *bus;
    struct usb_device   *dev;
    usb_dev_handle      *handle = 0;
    
    if ( _libusb_dylibHandle != NULL ) {
        
        int (*usbFindBusses) (void);
        usbFindBusses =  dlsym(_libusb_dylibHandle, "usb_find_busses");
        (*usbFindBusses)();
        
        int (*usbFindDevices) (void);
        usbFindDevices =  dlsym(_libusb_dylibHandle, "usb_find_devices");
        (*usbFindDevices)();
        
        int (*usbClose) (usb_dev_handle* udHandle);
        usbClose =  dlsym(_libusb_dylibHandle, "usb_close");
        
        usb_dev_handle * (*usbOpen) (struct usb_device *dev);
        usbOpen =  dlsym(_libusb_dylibHandle, "usb_open");
        
        char* (*usbErrorString) (void);
        usbErrorString =  dlsym(_libusb_dylibHandle, "usb_strerror");
        
        //?? use dlsym to get usb_busses structure ??
        struct usb_bus *usbBusses;
        usbBusses =  dlsym(_libusb_dylibHandle, "usb_busses");
        
        for(bus=usbBusses; bus; bus=bus->next){
            for(dev=bus->devices; dev; dev=dev->next){
                if(dev->descriptor.idVendor == USBDEV_SHARED_VENDOR && dev->descriptor.idProduct == USBDEV_SHARED_PRODUCT){
                    char    string[256];
                    int     len;
                    handle = (*usbOpen)(dev); /* we need to open the device in order to query strings */
                    if(!handle){
                        reportStatus([NSString stringWithFormat:@"Warning: cannot open USB device: %s\n", (*usbErrorString)()], CT_STATUS_LEVEL_RED);
                        continue;
                    }
                    /* now find out whether the device actually is obdev's Remote Sensor: */
                    len = usbGetStringAscii(handle, dev->descriptor.iManufacturer, 0x0409, string, sizeof(string));
                    if(len < 0){
                        reportStatus([NSString stringWithFormat:@"warning: cannot query manufacturer for device: %s\n", (*usbErrorString)()], CT_STATUS_LEVEL_RED);
                        goto skipDevice;
                    }
                    /* fprintf(stderr, "seen device from vendor ->%s<-\n", string); */
                    if(strcmp(string, "www.anyma.ch") != 0)
                        goto skipDevice;
                    len = usbGetStringAscii(handle, dev->descriptor.iProduct, 0x0409, string, sizeof(string));
                    if(len < 0){
                        reportStatus([NSString stringWithFormat:@"warning: cannot query product for device: %s\n", (*usbErrorString)()], CT_STATUS_LEVEL_RED);;
                        goto skipDevice;
                    }
                    /* fprintf(stderr, "seen product ->%s<-\n", string); */
                    if(strcmp(string, "uDMX") == 0)
                        break;
                skipDevice:
                    (*usbClose)(handle);
                    handle = NULL;
                }
            }
            if(handle)
                break;
        }
    }
    
    if( ! handle ) {
        reportStatus(@"Could not find uDMX device (www.anyma.ch/uDMX)", CT_STATUS_LEVEL_RED);
    }
    
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
    
    if ( _libusb_dylibHandle != NULL ) {
        dlclose(_libusb_dylibHandle);
        _libusb_dylibHandle = NULL;
    }
}

// dynamic linking allows library path to be an alias (often used to allow updates of a dylib)
+(void) getDylibHandle {
    if ( _libusb_dylibHandle == NULL ) {
        NSString* p = LXUSBDMX_LIBUSB_DRIVER_PATH;
        _libusb_dylibHandle = dlopen([p UTF8String], RTLD_NOW|RTLD_GLOBAL);
    }
}

-(void) startDevice {
    BOOL device_started = NO;
    
    [LXuDMXInterface getDylibHandle];
    
    if ( _libusb_dylibHandle ) {
        
        if ( ! _usb_init_called ) {
            void (*usbInit) (void);
            usbInit =  dlsym(_libusb_dylibHandle, "usb_init");
            (*usbInit)();
            
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
            device_started = YES;
        }
    }
    
    if ( device_started ) {
        [self statusChange:LXuDMX_STATE_BLUE];
    } else {
        [self statusChange:LXuDMX_STATE_RED];
    }
}

-(void) closeDevice {
    //stop listening for dmx received notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (  ( handle != NULL ) && ( _libusb_dylibHandle != NULL )) {
        
        int (*usbClose) (usb_dev_handle* udHandle);
        usbClose =  dlsym(_libusb_dylibHandle, "usb_close");
        
        if ( (*usbClose)(handle) != 0 ) {
            reportStatus(@"Error closing uDMX Connection", CT_STATUS_LEVEL_RED);
        }
        
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
        
        
        int (*usbCtrlMsg) (usb_dev_handle *dev, int requesttype, int request,
                           int value, int index, char *bytes, int size, int timeout);
        usbCtrlMsg =  dlsym(_libusb_dylibHandle, "usb_control_msg");
        
        int nBytes = (*usbCtrlMsg)(handle, USB_TYPE_VENDOR | USB_RECIP_DEVICE | USB_ENDPOINT_OUT,
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
