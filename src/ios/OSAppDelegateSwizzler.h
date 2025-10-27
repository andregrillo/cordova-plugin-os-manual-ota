//
//  OSAppDelegateSwizzler.h
//  OutSystems Manual OTA Plugin
//
//  Automatically swizzles AppDelegate methods to enable Background Fetch
//  and Silent Push Notifications without requiring manual AppDelegate modifications.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSAppDelegateSwizzler : NSObject

/**
 * Automatically called when the class loads.
 * Swizzles AppDelegate methods to intercept background operations.
 */
+ (void)load;

/**
 * Manually trigger swizzling (called automatically, but can be called explicitly if needed)
 */
+ (void)swizzleAppDelegateMethods;

@end

NS_ASSUME_NONNULL_END
