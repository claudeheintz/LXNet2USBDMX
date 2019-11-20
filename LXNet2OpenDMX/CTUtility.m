//
//  CTUtility.m
//  LXNet2USBDMX
//
//  Created by Claude Heintz on 6/25/16.
//  Copyright © 2016-2019 Claude Heintz. All rights reserved.
//
/*
 License is available at https://www.claudeheintzdesign.com/lx/opensource.html
 */

#import "CTUtility.h"
#include "ifaddrs.h"
#include <arpa/inet.h>
#include <netinet/in.h>

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

#pragma mark net utilities

//note network byte order reversed so 1st number of written is lsb
int ints2saddr(int d, int c, int b, int a) {
    return (a << 24) + (b << 16) + (c << 8) + d;
}

void packInt16Big(unsigned char* c, int i) {
    c[0] = ((i & 0xff00) >> 8);
    c[1] = i & 0xff;
}

void packInt16Little(unsigned char* c, int i) {
    c[1] = ((i & 0xff00) >> 8);
    c[0] = i & 0xff;
}

void packInt32Little(unsigned char* c, int i) {
    c[3] = ((i & 0xff000000) >> 24);
    c[2] = ((i & 0xff0000) >> 16);
    c[1] = ((i & 0xff00) >> 8);
    c[0] = i & 0xff;
}

BOOL equalSocketAddr(struct sockaddr_in a, struct sockaddr_in b) {
    if ( a.sin_family == b.sin_family) {
        if ( a.sin_port == b.sin_port) {
            if ( a.sin_addr.s_addr == b.sin_addr.s_addr) {
                return YES;
            }
        }
    }
    return NO;
}

NSArray* getNetIPAddresses() {
    NSMutableArray* addrarr=[[NSMutableArray alloc] init];
    struct ifaddrs *ifap, *ifa;
    int fam;
    const char* addr;
    if ( getifaddrs(&ifap) == 0 ) {
        ifa = ifap;
        while ( ifa != NULL ) {
            fam = ((struct sockaddr_in *) ifa->ifa_addr)->sin_family;
            if ( fam == AF_INET ) {
                addr = inet_ntoa(((struct sockaddr_in *) ifa->ifa_addr)->sin_addr);
                [addrarr addObject:[NSString stringWithCString:addr encoding:NSUTF8StringEncoding]];
            }
            ifa = ifa->ifa_next;
        }
    }
    return addrarr;
}

/*
 find a broadcast address for an IP address in the list of available interfaces
 use getifaddrs to retireive a linked list of ifaddrs structures
 find the one with the ip address matching the NSString addr
 and return the struct's broadcast address
*/

NSString* getBroadcastAddressForAddress(NSString* addr) {
    struct ifaddrs *ifap, *ifa;
    int fam;
    const char* ifaddr;
    if ( getifaddrs(&ifap) == 0 ) {
        ifa = ifap;
        while ( ifa != NULL ) {
            fam = ((struct sockaddr_in *) ifa->ifa_addr)->sin_family;
            if ( fam == AF_INET ) {
                ifaddr = inet_ntoa(((struct sockaddr_in *) ifa->ifa_addr)->sin_addr);
                if ( [addr isEqualToString:[NSString stringWithCString:ifaddr encoding:NSUTF8StringEncoding]] ) {
                    ifaddr = inet_ntoa(((struct sockaddr_in *) ifa->ifa_broadaddr)->sin_addr);
                    return [NSString stringWithCString:ifaddr encoding:NSUTF8StringEncoding];
                }
            }
            ifa = ifa->ifa_next;
        }
    }
    return NULL;
}
