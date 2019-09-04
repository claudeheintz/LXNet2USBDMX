//
//  CTUtility.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/25/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "CTUtility.h"

@implementation CTUtility

@end

BOOL isEmptyString(id str) {
    if ( [str respondsToSelector:@selector(length)] ) {
        return [str length] == 0;
    }
    return NO;
}

NSString* substringBeforeSeperator(NSString* s, NSString* ss) {
    NSRange pr = [s rangeOfString:ss];
    
    if ( pr.location != NSNotFound ) {
        return [s substringWithRange:NSMakeRange(0, pr.location)];
    }
    return NULL;
}

NSString* substringAfterSeperator(NSString* s, NSString* ss) {
    NSRange pr = [s rangeOfString:ss];
    
    if ( pr.location != NSNotFound ) {
        NSInteger loc = pr.location + [ss length];
        if ( loc <= [s length] ) {											//at end produces "" not NULL 6/16/11
            return [s substringWithRange:NSMakeRange(loc, [s length]-loc)];
        }
    }
    return NULL;
}

NSArray* substringsUsingSeperator(NSString* s, NSString* ss) {
    NSMutableArray* ra = [[NSMutableArray alloc] init];
    NSString* cs;
    NSString* rs = s;
    NSString* ts;
    BOOL done = NO;
    
    while ( (!done) && (cs = substringBeforeSeperator(rs, ss)) ) {
        [ra addObject:cs];
        ts = substringAfterSeperator( rs, ss );
        if ( ts ) {
            rs = ts;
        } else {
            done = YES;
        }
    }
    if ( rs && ([rs length] > 0) ) {
        [ra addObject:rs];
    }
    return ra;
}

int intFromHex (char a, char b) {
    return decodeHexCharacter(a)*16 + decodeHexCharacter(b);
}

int decodeHexCharacter(unichar cc) {
    if ( cc >= '0' && cc <='9' ) {
        return cc-'0';
    }
    if ( cc >= 'a' && cc <='f' ) {
        return cc-'a'+10;
    }
    if ( cc >= 'A' && cc <='F' ) {
        return cc-'A'+10;
    }
    return 0;
}
