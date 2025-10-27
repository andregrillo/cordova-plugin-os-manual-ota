//
//  OSAppDelegateSwizzler.m
//  OutSystems Manual OTA Plugin
//
//  Automatically swizzles AppDelegate methods to enable Background Fetch
//  and Silent Push Notifications without requiring manual AppDelegate modifications.
//

#import "OSAppDelegateSwizzler.h"
#import <objc/runtime.h>

// Forward declare Swift class interface
// The actual Swift header import is added to the app's Bridging-Header.h by our hook
// (hooks/after_prepare_setup_bridging_header.js)
//
// This forward declaration allows compilation and provides type information.
// At runtime, we verify the class exists before calling it.
@interface OSBackgroundUpdateManager : NSObject
+ (instancetype)shared;
- (void)performBackgroundFetchWithCompletion:(void (^)(UIBackgroundFetchResult))completion;
- (void)handleSilentPushNotificationWithUserInfo:(NSDictionary *)userInfo
                                       completion:(void (^)(UIBackgroundFetchResult))completion;
@end

@implementation OSAppDelegateSwizzler

#pragma mark - Automatic Loading

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"🔧 [OSManualOTA] Swizzler loading...");

        // Wait a bit for AppDelegate to be ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self swizzleAppDelegateMethods];
        });
    });
}

#pragma mark - Swizzling

+ (void)swizzleAppDelegateMethods {
    // Verify Swift class is available at runtime
    Class swiftManagerClass = NSClassFromString(@"OSBackgroundUpdateManager");
    if (!swiftManagerClass) {
        NSLog(@"❌ [OSManualOTA] Swift class OSBackgroundUpdateManager not found!");
        NSLog(@"   This might indicate a bridging header issue.");
        return;
    }
    NSLog(@"✅ [OSManualOTA] Swift class OSBackgroundUpdateManager found");

    // Get AppDelegate class
    Class appDelegateClass = [self getAppDelegateClass];

    if (!appDelegateClass) {
        NSLog(@"⚠️  [OSManualOTA] Could not find AppDelegate class");
        return;
    }

    NSLog(@"✅ [OSManualOTA] Found AppDelegate: %@", NSStringFromClass(appDelegateClass));

    // Swizzle Background Fetch
    [self swizzleBackgroundFetchForClass:appDelegateClass];

    // Swizzle Silent Push
    [self swizzleSilentPushForClass:appDelegateClass];

    NSLog(@"✅ [OSManualOTA] AppDelegate methods swizzled successfully!");
}

#pragma mark - Get AppDelegate Class

+ (Class)getAppDelegateClass {
    // Try to get AppDelegate from UIApplication
    id appDelegate = [[UIApplication sharedApplication] delegate];

    if (appDelegate) {
        return [appDelegate class];
    }

    // Fallback: Try to find AppDelegate class by name
    Class appDelegateClass = NSClassFromString(@"AppDelegate");
    if (appDelegateClass) {
        return appDelegateClass;
    }

    return nil;
}

#pragma mark - Swizzle Background Fetch

+ (void)swizzleBackgroundFetchForClass:(Class)appDelegateClass {
    SEL originalSelector = @selector(application:performFetchWithCompletionHandler:);
    SEL swizzledSelector = @selector(osmanualota_application:performFetchWithCompletionHandler:);

    Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);

    if (!swizzledMethod) {
        NSLog(@"❌ [OSManualOTA] Swizzled method not found!");
        return;
    }

    // If original method doesn't exist, add it
    if (!originalMethod) {
        NSLog(@"ℹ️  [OSManualOTA] performFetchWithCompletionHandler not found, adding it");

        // Add our method as the original
        class_addMethod(appDelegateClass,
                       originalSelector,
                       method_getImplementation(swizzledMethod),
                       method_getTypeEncoding(swizzledMethod));
    } else {
        // Method exists, swap implementations
        NSLog(@"ℹ️  [OSManualOTA] performFetchWithCompletionHandler found, swizzling it");

        // Try to add our method first
        BOOL didAddMethod = class_addMethod(appDelegateClass,
                                           originalSelector,
                                           method_getImplementation(swizzledMethod),
                                           method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            // Successfully added, now replace with original
            class_replaceMethod(appDelegateClass,
                              swizzledSelector,
                              method_getImplementation(originalMethod),
                              method_getTypeEncoding(originalMethod));
        } else {
            // Already exists, swap
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    }

    NSLog(@"✅ [OSManualOTA] Background Fetch swizzled");
}

#pragma mark - Swizzle Silent Push

+ (void)swizzleSilentPushForClass:(Class)appDelegateClass {
    SEL originalSelector = @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:);
    SEL swizzledSelector = @selector(osmanualota_application:didReceiveRemoteNotification:fetchCompletionHandler:);

    Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);

    if (!swizzledMethod) {
        NSLog(@"❌ [OSManualOTA] Swizzled method not found!");
        return;
    }

    // If original method doesn't exist, add it
    if (!originalMethod) {
        NSLog(@"ℹ️  [OSManualOTA] didReceiveRemoteNotification not found, adding it");

        // Add our method as the original
        class_addMethod(appDelegateClass,
                       originalSelector,
                       method_getImplementation(swizzledMethod),
                       method_getTypeEncoding(swizzledMethod));
    } else {
        // Method exists, swap implementations
        NSLog(@"ℹ️  [OSManualOTA] didReceiveRemoteNotification found, swizzling it");

        // Try to add our method first
        BOOL didAddMethod = class_addMethod(appDelegateClass,
                                           originalSelector,
                                           method_getImplementation(swizzledMethod),
                                           method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            // Successfully added, now replace with original
            class_replaceMethod(appDelegateClass,
                              swizzledSelector,
                              method_getImplementation(originalMethod),
                              method_getTypeEncoding(originalMethod));
        } else {
            // Already exists, swap
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    }

    NSLog(@"✅ [OSManualOTA] Silent Push swizzled");
}

#pragma mark - Swizzled Method Implementations

- (void)osmanualota_application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    NSLog(@"🔄 [OSManualOTA] Background Fetch intercepted!");

    // Call our plugin's background update manager
    [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];

    // Note: We don't call the original method because we handle everything in our manager
    // If the original method exists and you want to call it too, you can do:
    // [self osmanualota_application:application performFetchWithCompletionHandler:completionHandler];
    // (this works because methods are swapped, so calling our method actually calls the original)
}

- (void)osmanualota_application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    NSLog(@"🔔 [OSManualOTA] Remote Notification intercepted!");
    NSLog(@"📦 Notification payload: %@", userInfo);

    // Check if this is an OTA update notification
    if (userInfo[@"ota_update"]) {
        NSLog(@"✅ [OSManualOTA] OTA update notification detected");

        // Handle via our plugin
        [[OSBackgroundUpdateManager shared] handleSilentPushNotificationWithUserInfo:userInfo
                                                                          completion:completionHandler];
    } else {
        NSLog(@"ℹ️  [OSManualOTA] Not an OTA notification, passing through");

        // Not an OTA notification, call original implementation if it exists
        // This ensures other push notifications still work
        if ([self respondsToSelector:@selector(osmanualota_application:didReceiveRemoteNotification:fetchCompletionHandler:)]) {
            [self osmanualota_application:application
               didReceiveRemoteNotification:userInfo
                     fetchCompletionHandler:completionHandler];
        } else {
            // No original implementation, just complete
            completionHandler(UIBackgroundFetchResultNoData);
        }
    }
}

@end
