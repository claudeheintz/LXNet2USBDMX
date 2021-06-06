//
//  LXOpenDMXInterface.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/23/16.
//
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "LXOpenDMXInterface.h"
#import "LXDMXEthernetInterface.h"
#import "LXDMXReceivedMessage.h"
#import "CTStatusReporter.h"

#include <dlfcn.h>

/*
 *  dynamic library handle for resolving symbols
 */
void* _libdf2xx_dylibHandle = NULL;


@implementation LXOpenDMXInterface


-(id) init {
    self = [super init];
    
    if ( self ) {
        device_handle = NULL;
        sending = NO;
        active = NO;
        universe = 0;                                    // hard coded universe!
        memset((void*)_dmxdata, 0, 513);
    }
    
    return self;
}

// dynamic linking allows library path to be an alias (often used to allow updates of a dylib)
+(void) getDylibHandle {
    if ( _libdf2xx_dylibHandle == NULL ) {
        NSString* p = LXUSBDMX_FTDID2XX_DRIVER_PATH;
        _libdf2xx_dylibHandle = dlopen([p UTF8String], RTLD_NOW|RTLD_GLOBAL);
    }
}


/**
 *  attempt to open device connection
 */
-(BOOL) openConnection {
    if ( device_handle != NULL ) {
        return YES;
    }
    
    [LXOpenDMXInterface getDylibHandle];
    
    if ( _libdf2xx_dylibHandle != NULL ) {
    
        FT_HANDLE rh = NULL;
        FT_STATUS ft_Status = 1;
        int tries =0;
        
        
        while ((ft_Status != FT_OK) && (tries < 3))  {
            
            FT_STATUS (*ftOpen) (int deviceNumber,
                                 FT_HANDLE *pHandle);
            ftOpen =  dlsym(_libdf2xx_dylibHandle, "FT_Open");
            
            ft_Status = (*ftOpen)(0, &rh);				//try first device found
            if (ft_Status == FT_OK) {
                device_handle = rh;
                [CTStatusReporter reportStatus:@"D2XX connection opened by device" level:CT_STATUS_LEVEL_GREEN];
                return YES;
            }
            
            [NSThread sleepForTimeInterval:0.1];
            tries++;
        }

        [CTStatusReporter alertUserToStatus:[NSString stringWithFormat:@"d2xx connection error: %@", [self ftErrorString:ft_Status]] level:CT_STATUS_INFORM_USER_RED];
        
    }       //<-_libdf2xx_dylibHandle != NULL

    return NO;
}

-(BOOL) setupCommParameters {
    FT_STATUS ft_Status = FT_INVALID_HANDLE;
    
    if ( _libdf2xx_dylibHandle != NULL ) {
        
        FT_STATUS (*ftSetBaud) (FT_HANDLE ftHandle, ULONG BaudRate );
        ftSetBaud =  dlsym(_libdf2xx_dylibHandle, "FT_SetBaudRate");
    
        ft_Status = (*ftSetBaud)(device_handle, 250000);
        if ( ft_Status == FT_OK ) {
            
            FT_STATUS (*ftSetDataCharacteristics) (FT_HANDLE ftHandle, UCHAR WordLength,
                                                   UCHAR StopBits, UCHAR Parity);
            ftSetDataCharacteristics =  dlsym(_libdf2xx_dylibHandle, "FT_SetDataCharacteristics");
            
            ft_Status = (*ftSetDataCharacteristics)(device_handle, FT_BITS_8, FT_STOP_BITS_2, FT_PARITY_NONE);
            if ( ft_Status == FT_OK ) {
                
                FT_STATUS (*ftSetDataFlowControl) (FT_HANDLE ftHandle, USHORT FlowControl,
                                                    UCHAR XonChar, UCHAR XoffChar);
                ftSetDataFlowControl =  dlsym(_libdf2xx_dylibHandle, "FT_SetFlowControl");
                
                ft_Status = (*ftSetDataFlowControl)(device_handle, FT_FLOW_NONE, 0, 0);
                if ( ft_Status == FT_OK ) {
                    return YES;
                }
            }
        }
        
    }       //<-_libdf2xx_dylibHandle != NULL
    
    [CTStatusReporter alertUserToStatus:[NSString stringWithFormat:@"d2xx connection error: %@", [self ftErrorString:ft_Status]] level:CT_STATUS_INFORM_USER_RED];
    return NO;
}

-(NSString*) ftErrorString:(int) code {
    if ( code > 0 ) {
        switch ( code ) {
            case 1:
                return @"FT_INVALID_HANDLE";
                break;
            case 2:
                return @"FT_DEVICE_NOT_FOUND";
                break;
            case 3:
                return @"FT_DEVICE_NOT_OPENED";
                break;
            case 4:
                return @"FT_IO_ERROR";
                break;
            case 5:
                return @"FT_INSUFFICIENT_RESOURCES";
                break;
            case 6:
                return @"FT_INVALID_PARAMETER";
                break;
            case 7:
                return @"FT_INVALID_BAUD_RATE";
                break;
        }
    }
    return [NSString stringWithFormat:@"FT_STATUS %i", code];
}

-(void) statusChange:(NSUInteger) status {
    [self performSelectorOnMainThread:@selector(postStatusChange:) withObject:[NSNumber numberWithInteger:status] waitUntilDone:NO];
}

-(void) postStatusChange:(NSNumber*) change {
    [[NSNotificationCenter defaultCenter] postNotificationName:LXOPENDMX_STATUS_CHANGE_NOTIFICATION object:change];
}

-(void) startSending {
    if ( [self openConnection] ) {
        if ( [self setupCommParameters] ) {
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(DMXReceived:)
                                                         name: LXDMX_RECEIVE_NOTIFICATION
                                                       object: nil];
            sending = YES;
            [NSThread detachNewThreadSelector:@selector(sendDMX) toTarget:self withObject:NULL];
            [self statusChange:2];
        } else {
            [self statusChange:1];
        }
    } else {
        [self statusChange:1];
    }
}

-(void) stopSending {
    sending = NO;
    
    // wait for sending thread to exit
    while ( active ) {
        [NSThread sleepForTimeInterval:0.01];
    }
    
    // close the connection to the D2XX device
    if ( device_handle != NULL ) {
        
        FT_STATUS (*ftClose) (FT_HANDLE *pHandle);
        ftClose =  dlsym(_libdf2xx_dylibHandle, "FT_Close");
        
        (*ftClose)(device_handle);
        device_handle = NULL;
    }
    
    //stop listening for dmx received notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    //post the status
    [self statusChange:0];
    [CTStatusReporter reportStatus:@"Stopped DMX." level:CT_STATUS_LEVEL_NOLOG_INFO];
}

-(BOOL) isSending {
    return sending && ( device_handle != NULL ) ;
}

-(BOOL) checkSendingError:(FT_STATUS) s {
    if ( s != FT_OK ) {
        if ( device_handle != NULL ) {
            
            FT_STATUS (*ftClose) (FT_HANDLE *pHandle);
            ftClose =  dlsym(_libdf2xx_dylibHandle, "FT_Close");
            
            (*ftClose)(device_handle);
            device_handle = NULL;
        }
        [self statusChange:1];
    }
    return sending;
}

-(void) sendDMX {
    uint32_t bytesWritten;
    active = YES;
    id activity = NULL;
    
    if ( [[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)] ) {
        NSActivityOptions options = NSActivityLatencyCritical | NSActivityUserInitiated;
        // NSActivityLatencyCritical   NSActivityUserInitiated 0x00FFFFFF  NSActivityUserInitiatedAllowingIdleSystemSleep
        activity = [[NSProcessInfo processInfo] beginActivityWithOptions:options
                                                                    reason:@"Open DMX Send"];
    }
    [NSThread setThreadPriority:0.8];
    FT_STATUS s;
    
    struct timeval tvs, tvc;
    double elapsed;
    
    while ( sending ) {
        if ( device_handle == NULL ) {
            if ( [self openConnection] ) {
                if ( [self setupCommParameters] ) {
                    sending = YES;
                    [CTStatusReporter alertUserToStatus:@"Restored connection" level:CT_STATUS_LEVEL_NOLOG_GREEN];
                    [self statusChange:2];
                } else {
                    [self checkSendingError:FT_OTHER_ERROR];
                }
            } else {
                [self checkSendingError:FT_OTHER_ERROR];
                [NSThread sleepForTimeInterval:3];      //can't re-open yet, wait 3 secs before looping & trying again
            }
        } else {
    
            FT_STATUS (*ftSetBreakOn) (FT_HANDLE *pHandle);
            ftSetBreakOn =  dlsym(_libdf2xx_dylibHandle, "FT_SetBreakOn");
            
            s = (*ftSetBreakOn)(device_handle);
            if ( [self checkSendingError:s] ) {
                usleep(DMX_BREAK_USEC);
                
                FT_STATUS (*ftSetBreakOff) (FT_HANDLE *pHandle);
                ftSetBreakOff =  dlsym(_libdf2xx_dylibHandle, "FT_SetBreakOff");
                
                s = (*ftSetBreakOff)(device_handle);
                if ( [self checkSendingError:s] ) {
                    usleep(DMX_MAB_USEC);
                    gettimeofday(&tvs, NULL);
                    
                    @synchronized(self) {
                        
                        FT_STATUS (*ftWrite) (FT_HANDLE *pHandle, LPVOID lpBuffer,
                                              DWORD nBufferSize, LPDWORD lpBytesWritten);
                        ftWrite =  dlsym(_libdf2xx_dylibHandle, "FT_Write");
                        
                        s = (*ftWrite)(device_handle, (void*)_dmxdata, 513, &bytesWritten);
                    }
                    if ( [self checkSendingError:s] ) {
                        gettimeofday(&tvc, NULL);
                        elapsed = ((tvc.tv_sec-tvs.tv_sec)*1000000.0 + ((tvc.tv_usec-tvs.tv_usec)));
                        if ( elapsed < DMX_PACKET_USEC ) {
                            usleep(DMX_PACKET_USEC-elapsed);
                        }
                    }       // write  == FT_OK
                }           // bk off == FT_OK
            }               // bk on  == FT_OK
        }                   // device != NULL
    }                       // while
    
    if ( activity ) {
        if ( [[NSProcessInfo processInfo] respondsToSelector:@selector(endActivity:) ] ) {
            [[NSProcessInfo processInfo] endActivity:activity];
            activity = NULL;
        }
    }
    
    active = NO;
}

-(void) DMXReceived:(NSNotification*) note {
    if ( [[note object] receivedUniverse] == universe ) {
        uint8_t* idmx = [[note object] DMXArrayForRead];
        @synchronized(self) {
            for ( int i=0; i<DMX_DIMMERS_IN_UNIVERSE; i++ ) {
                _dmxdata[i+1] = idmx[i];
            }
        }
    }
}

@end
