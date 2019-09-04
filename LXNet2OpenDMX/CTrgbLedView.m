//
//  CTrgbLedView.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/26/16.
//  Copyright © 2016-2019 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "CTrgbLedView.h"

@implementation CTrgbLedView

@synthesize path;
@synthesize ledstate = _ledstate;

-(id) initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    
    if ( self ) {
        [self setFrame:self.frame];
        self.ledstate = CTRGB_LED_STATE_OFF;
    }
    
    return self;
}

-(id) initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    
    if ( self ) {
        [self setFrame:self.frame];
        self.ledstate = CTRGB_LED_STATE_OFF;
    }
    
    return self;
}

-(void) setFrame:(NSRect)frame {
    [super setFrame:frame];
    CGFloat d = fmin(frame.size.width,frame.size.height);
    NSRect prect = NSMakeRect(1, 1, d-1, d-1);
    self.path = [NSBezierPath bezierPathWithOvalInRect:prect];
}

-(NSUInteger) ledstate {
    return _ledstate;
}

-(void) setLedstate:(NSUInteger) s {
    _ledstate = s;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    switch ( self.ledstate ) {
        case CTRGB_LED_STATE_OFF:
            [[NSColor colorWithRed:0 green:0 blue:0 alpha:0] setFill];
            break;
        case CTRGB_LED_STATE_RED:
            [[NSColor redColor] setFill];
            break;
        case CTRGB_LED_STATE_GREEN:
            [[NSColor greenColor] setFill];
            break;
        case CTRGB_LED_STATE_BLUE:
            [[NSColor blueColor] setFill];
            break;
        case CTRGB_LED_STATE_YELLOW:
            [[NSColor yellowColor] setFill];
            break;
        case CTRGB_LED_STATE_ORANGE:
            [[NSColor orangeColor] setFill];
            break;
    }
    
    [self.path fill];
}

@end
