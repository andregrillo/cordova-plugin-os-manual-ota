//
//  OSCacheHelper.h
//  OutSystems Manual OTA Plugin
//
//  Helper class to compute cache paths using OutSystems hashing
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSCacheHelper : NSObject

/**
 * Compute the cache directory key using the same hash algorithm as OutSystems
 * This matches the logic in OSNativeCache.m keyForHostname:andApplication:
 * @param hostname The hostname (e.g., "personal-abc.outsystemscloud.com")
 * @param application The application path (e.g., "/MyApp")
 * @return The hashed key as a string
 */
+ (NSString *)cacheKeyForHostname:(NSString *)hostname andApplication:(NSString *)application;

@end

NS_ASSUME_NONNULL_END
