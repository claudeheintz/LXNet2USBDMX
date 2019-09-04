//
//  CTUtility.h
//  LXNet2OpenDMX
//
//  Created by Claude Heintz on 6/25/16.
//  Copyright © 2016 Claude Heintz. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CTUtility : NSObject

@end


BOOL isEmptyString(id str);
NSString* substringBeforeSeperator(NSString* s, NSString* ss);
NSString* substringAfterSeperator(NSString* s, NSString* ss);
NSArray* substringsUsingSeperator(NSString* s, NSString* ss);
int intFromHex (char a, char b);
int decodeHexCharacter(unichar cc);
