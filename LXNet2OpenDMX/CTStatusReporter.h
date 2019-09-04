//
//  CTStatusReporter.h
//  LXNet2OpenDMX
//
//  Created by Claude Heintz on 6/25/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CTStatusReporter : NSObject {
    NSString* status;
    NSUInteger level;
}

@property (retain) NSString* status;
@property (assign) NSUInteger level;

/*
 * initialize a status reporter object
 * sstr is status message
 * l is reporing level
 */
-(id) initWithMessage:(NSString*) sstr level:(NSUInteger) l;

/*
 * postStatus informs interested parties of a new status
 * should be called from performSelectorOnMainThread so receivers can update UI safely
 * called by class method reportStatus:level: passing the CTStatusReporter as the object
 */
-(void) postStatus:(id) obj;

/*
 * sets a flag indicating that the status should be brought to the user's attention
 */
-(BOOL) shouldInformUser;

/*
 * indicates that a window should alert a user if the inform flag has been set
 * the status may be ignored
 */
-(BOOL) checkAndAlertUser;

/*
 * used by any client to post a status message
 * level informs listeners of importance
 * posts a notification with a LXStausReporter as the object
 */
+(void) reportStatus:(NSString*) sstr level:(NSInteger) level;

/*
 * used by any client to log a status message
 * 
 */
+(void) reportStatus:(NSString*) sstr;

/*
 * used to post an inform status followed by alertUserIfNeeded
 */
+(void) alertUserToStatus:(NSString*) sstr level:(NSInteger) level;

/*
 * used by any client to log a debug status message if a flag is set
 */
+(void) reportStatus:(NSString*) sstr flag:(BOOL) f;

/*
 * calls reportStatus:NULL level:CT_STATUS_CHECK_AND_ALERT
 */
+(void) alertUserIfNeeded;

@end

#define CTSTATUS_UPDATE_NOTIFICATION @"CTSTATUS_UPDATE_NOTIF"

//These levels post a notification and log the status
#define CT_STATUS_LEVEL_RED    1
#define CT_STATUS_LEVEL_YELLOW 2
#define CT_STATUS_LEVEL_GREEN  3
#define CT_STATUS_LEVEL_INFO   4

//these levels do not post a notification
#define CT_STATUS_LEVEL_LOG   10
#define CT_STATUS_LEVEL_DEBUG 11

//these levels post a notification without a log entry
#define CT_STATUS_NOLOG              16
#define CT_STATUS_LEVEL_NOLOG_RED    17
#define CT_STATUS_LEVEL_NOLOG_YELLOW 18
#define CT_STATUS_LEVEL_NOLOG_GREEN  19
#define CT_STATUS_LEVEL_NOLOG_INFO   20

//these flags indicate a window should inform the user of the status
#define CT_STATUS_INFORM_USER       32
#define CT_STATUS_INFORM_USER_RED   33

//this flag signials that the user should be alerted if the inform flag has been set
//send this notification without a status (includes no log flag)
#define CT_STATUS_SHOULD_CHECK_AND_ALERT 64
#define CT_STATUS_CHECK_AND_ALERT        80

