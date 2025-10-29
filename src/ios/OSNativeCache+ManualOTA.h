//
//  OSNativeCache+ManualOTA.h
//  OutSystems Manual OTA Plugin
//
//  Category extension to expose internal OSNativeCache methods needed for
//  manual OTA cache swapping after background downloads
//

#import <Foundation/Foundation.h>
#import "OSNativeCache.h"

// Forward declarations
@class OSApplicationCache;
@class OSCacheResources;
@class OSThreadSafeDictionaryWrapper;

@interface OSNativeCache (ManualOTA)

/**
 * Changes the current cache status
 * @param status The new status to set
 */
- (void)changeCacheStatus:(OSCacheStatus)status;

/**
 * Swaps the currently ongoing cache resources to be the active/running version
 * @return YES if swap was successful, NO otherwise
 */
- (BOOL)swapCache;

/**
 * Gets the application cache entries dictionary (thread-safe wrapper)
 * @return Thread-safe dictionary wrapper mapping application keys to OSApplicationCache objects
 */
- (OSThreadSafeDictionaryWrapper*)applicationEntries;

/**
 * Gets the ongoing cache resources being downloaded
 * @return The OSCacheResources object for the version being downloaded
 */
- (OSCacheResources*)ongoingCacheResources;

/**
 * Sets the ongoing cache resources
 * @param resources The cache resources to set as ongoing
 */
- (void)setOngoingCacheResources:(OSCacheResources*)resources;

/**
 * Writes the cache manifest to disk
 * Call this after swapping cache to persist changes
 */
- (void)writeCacheManifest;

@end
