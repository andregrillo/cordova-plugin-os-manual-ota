//
//  OSNativeCache+ManualOTA.m
//  OutSystems Manual OTA Plugin
//
//  This category doesn't need to implement anything - it just declares
//  the interface to allow Swift code to call these existing private methods.
//
//  The actual implementations already exist in OSNativeCache.m
//

#import "OSNativeCache+ManualOTA.h"

@implementation OSNativeCache (ManualOTA)

// No implementation needed - we're just declaring the interface
// The methods already exist in OSNativeCache.m as private methods:
// - changeCacheStatus: (line 539)
// - swapCache (line 468)
// - applicationEntries is a property (line 113)
// - _ongoingCacheResources is a property (line 110)

@end
