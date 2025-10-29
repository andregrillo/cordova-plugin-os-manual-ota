//
//  OSCacheHelper.m
//  OutSystems Manual OTA Plugin
//
//  Helper class to compute cache paths using OutSystems hashing
//

#import "OSCacheHelper.h"

@implementation OSCacheHelper

+ (NSString *)cacheKeyForHostname:(NSString *)hostname andApplication:(NSString *)application {
    // This replicates the exact logic from OSNativeCache.m:1045-1050
    // +(NSString*) keyForHostname:(NSString*)hostname andApplication:(NSString*)application{
    //     NSString *appKey = [NSString stringWithFormat:@"%@/%@",hostname,application];
    //     return [NSString stringWithFormat:@"%lu", (unsigned long)[appKey hash]];
    // }

    NSString *appKey = [NSString stringWithFormat:@"%@/%@", hostname, application];
    NSUInteger hash = [appKey hash];

    return [NSString stringWithFormat:@"%lu", (unsigned long)hash];
}

@end
