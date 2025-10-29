//
//  OSManualOTA-Bridging-Header.h
//  OutSystems Manual OTA Plugin
//
//  Bridging header to expose OutSystems Objective-C classes to Swift
//

#import <Cordova/CDV.h>

// OutSystems Core Plugin Headers
#import "OSCache.h"
#import "OSNativeCache.h"
#import "OSCacheResources.h"
#import "OSApplicationCache.h"
#import "OSPreBundle.h"
#import "OSCacheEntry.h"
#import "OSManifestParser.h"
#import "OSLogger.h"
#import "OSThreadSafeDictionaryWrapper.h"

// OSManualOTA Plugin Headers (Objective-C classes accessible to Swift)
#import "OSBackgroundUpdateManager.h"
#import "OSCacheHelper.h"
#import "OSNativeCache+ManualOTA.h"
