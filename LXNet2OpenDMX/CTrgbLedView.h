//
//  CTrgbLedView.h
//  LXNet2OpenDMX
//
//  Created by Claude Heintz on 6/26/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface CTrgbLedView : NSView {
    NSBezierPath* path;
    NSUInteger _ledstate;
}

@property (retain) NSBezierPath* path;
@property (assign) NSUInteger ledstate;

@end

#define CTRGB_LED_STATE_OFF     0
#define CTRGB_LED_STATE_RED     1
#define CTRGB_LED_STATE_GREEN   2
#define CTRGB_LED_STATE_BLUE    3
#define CTRGB_LED_STATE_YELLOW  4
#define CTRGB_LED_STATE_ORANGE  5
