//
//  OSBackgroundUpdateManager.h
//  OutSystems Manual OTA Plugin
//
//  Handles Background Fetch and Silent Push Notifications for automatic updates
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Manages background update operations for the OSManualOTA plugin.
 * Handles Background Fetch (iOS 7+) and BGAppRefreshTask (iOS 13+).
 */
@interface OSBackgroundUpdateManager : NSObject

/**
 * Singleton instance
 */
+ (instancetype)shared;

/**
 * Handle Background Fetch callback from AppDelegate
 * @param completion Completion handler to call with fetch result
 */
- (void)performBackgroundFetchWithCompletion:(void (^)(UIBackgroundFetchResult))completion;

/**
 * Handle Silent Push Notification from AppDelegate
 * @param userInfo The notification payload
 * @param completion Completion handler to call with fetch result
 */
- (void)handleSilentPushNotificationWithUserInfo:(NSDictionary *)userInfo
                                      completion:(void (^)(UIBackgroundFetchResult))completion;

/**
 * Schedule the next BGAppRefreshTask (iOS 13+)
 * No-op on iOS < 13
 */
- (void)scheduleAppRefreshTask;

/**
 * Set the minimum background fetch interval
 * @param interval Time interval in seconds
 */
- (void)setMinimumBackgroundFetchInterval:(NSTimeInterval)interval;

/**
 * Enable or disable background updates
 * @param enabled YES to enable, NO to disable
 */
- (void)enableBackgroundUpdates:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
