//
//  CTStatusReporter.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/25/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "CTStatusReporter.h"

@implementation CTStatusReporter
@synthesize status;
@synthesize level;

-(id) initWithMessage:(NSString*) sstr level:(NSUInteger) l {
    self = [super init];
    
    if ( self ) {
        self.status = sstr;
        self.level = l;
    }
    
    return self;
}

-(void) postStatus:(id) obj {
    [[NSNotificationCenter defaultCenter] postNotificationName:CTSTATUS_UPDATE_NOTIFICATION object:obj];
}

-(BOOL) shouldInformUser {
    return (level & CT_STATUS_INFORM_USER) != 0;
}

-(BOOL) checkAndAlertUser {
    return (level & CT_STATUS_SHOULD_CHECK_AND_ALERT) != 0;
}

+(void) reportStatus:(NSString*) sstr level:(NSInteger) level {
    if ( (level & CT_STATUS_NOLOG) == 0 )  {
        NSLog(@"%@", sstr);
    }
    if ( (level & 0x0F) < CT_STATUS_LEVEL_LOG )  {
        CTStatusReporter* sr = [[CTStatusReporter alloc] initWithMessage:sstr level:level];
        [sr performSelectorOnMainThread:@selector(postStatus:) withObject:sr waitUntilDone:NO];
    }
}

+(void) reportStatus:(NSString*) sstr {
    [CTStatusReporter reportStatus:sstr level:CT_STATUS_LEVEL_LOG];
}

+(void) alertUserToStatus:(NSString*) sstr level:(NSInteger) level {
    if ( ( level & CT_STATUS_INFORM_USER ) == 0 ) {
        [CTStatusReporter reportStatus:sstr level:(level | CT_STATUS_INFORM_USER)];
    } else {
        [CTStatusReporter reportStatus:sstr level:level];
    }
    [CTStatusReporter alertUserIfNeeded];
}

+(void) reportStatus:(NSString*) sstr flag:(BOOL) f {
    if ( f ) {
        [CTStatusReporter reportStatus:sstr level:CT_STATUS_LEVEL_DEBUG];
    }
}

+(void) alertUserIfNeeded {
    [CTStatusReporter reportStatus:NULL level:CT_STATUS_CHECK_AND_ALERT];
}

@end

