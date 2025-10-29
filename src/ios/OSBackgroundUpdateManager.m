//
//  OSBackgroundUpdateManager.m
//  OutSystems Manual OTA Plugin
//
//  Handles Background Fetch and Silent Push Notifications for automatic updates
//

#import "OSBackgroundUpdateManager.h"
#import <BackgroundTasks/BackgroundTasks.h>

// Import the Swift-to-Objective-C generated header
// This allows us to access Swift classes from Objective-C
#if __has_include("OTA_Test-Swift.h")
    #import "OTA_Test-Swift.h"
#elif __has_include("OutSystems-Swift.h")
    #import "OutSystems-Swift.h"
#else
    // Forward declare the Swift class if header not available
    @interface OSManualOTAManager : NSObject
    + (instancetype)shared;
    - (void)checkForUpdatesWithCompletion:(void (^)(BOOL, NSString * _Nullable, NSError * _Nullable))completion;
    - (void)downloadUpdateWithProgressHandler:(void (^ _Nullable)(NSInteger, NSInteger, NSInteger))progressHandler
                                  errorHandler:(void (^ _Nullable)(NSString * _Nonnull))errorHandler
                                    completion:(void (^)(BOOL))completion;
    - (void)applyUpdateWithCompletion:(void (^)(BOOL, NSError * _Nullable))completion;
    @end
#endif

@interface OSBackgroundUpdateManager ()

@property (nonatomic, strong) OSManualOTAManager *otaManager;
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;
@property (nonatomic, copy) NSString *backgroundTaskIdentifier;

@end

@implementation OSBackgroundUpdateManager

#pragma mark - Singleton

+ (instancetype)shared {
    static OSBackgroundUpdateManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _otaManager = [OSManualOTAManager shared];
        _backgroundTask = UIBackgroundTaskInvalid;
        _backgroundTaskIdentifier = @"com.outsystems.manual-ota.refresh";
        [self registerBackgroundTasks];
    }
    return self;
}

#pragma mark - Background Fetch (iOS 7+)

- (void)performBackgroundFetchWithCompletion:(void (^)(UIBackgroundFetchResult))completion {
    NSLog(@"🔄 Background Fetch triggered - checking for OTA updates...");

    // Start background task to ensure we have time to complete
    [self startBackgroundTask];

    __weak OSBackgroundUpdateManager *weakSelf = self;
    [self.otaManager checkForUpdatesWithCompletion:^(BOOL hasUpdate, NSString * _Nullable version, NSError * _Nullable error) {
        __strong OSBackgroundUpdateManager *strongSelf = weakSelf;
        if (!strongSelf) {
            completion(UIBackgroundFetchResultFailed);
            return;
        }

        if (error) {
            NSLog(@"❌ Background fetch check failed: %@", error.localizedDescription);
            [strongSelf endBackgroundTask];
            completion(UIBackgroundFetchResultFailed);
            return;
        }

        if (hasUpdate) {
            NSLog(@"✅ Update available: %@", version ?: @"unknown");

            // Download the update in background
            [strongSelf downloadUpdateInBackgroundWithCompletion:^(BOOL success) {
                [strongSelf endBackgroundTask];
                if (success) {
                    NSLog(@"✅ Background update download completed");
                    completion(UIBackgroundFetchResultNewData);

                    // Notify user (optional)
                    [strongSelf showUpdateAvailableNotificationWithVersion:version];
                } else {
                    NSLog(@"❌ Background update download failed");
                    completion(UIBackgroundFetchResultFailed);
                }
            }];
        } else {
            NSLog(@"ℹ️ No update available");
            [strongSelf endBackgroundTask];
            completion(UIBackgroundFetchResultNoData);
        }
    }];
}

#pragma mark - BGAppRefreshTask (iOS 13+)

- (void)registerBackgroundTasks {
    if (@available(iOS 13.0, *)) {
        __weak OSBackgroundUpdateManager *weakSelf = self;
        [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:self.backgroundTaskIdentifier
                                                               usingQueue:nil
                                                            launchHandler:^(__kindof BGTask * _Nonnull task) {
            __strong OSBackgroundUpdateManager *strongSelf = weakSelf;
            if (strongSelf && [task isKindOfClass:[BGAppRefreshTask class]]) {
                [strongSelf handleAppRefreshTask:(BGAppRefreshTask *)task];
            }
        }];
    }
}

- (void)handleAppRefreshTask:(BGAppRefreshTask *)task API_AVAILABLE(ios(13.0)) {
    NSLog(@"🔄 BGAppRefreshTask triggered - checking for OTA updates...");

    // Schedule next refresh
    [self scheduleAppRefreshTask];

    // Create operation for the task
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
        [self performBackgroundUpdateCheckWithCompletion:^(UIBackgroundFetchResult result) {
            [task setTaskCompletedWithSuccess:(result == UIBackgroundFetchResultNewData)];
        }];
    }];

    // Handle task expiration
    task.expirationHandler = ^{
        [operation cancel];
        NSLog(@"⚠️ BGAppRefreshTask expired");
    };

    // Start operation
    [operation start];
}

- (void)scheduleAppRefreshTask {
    if (@available(iOS 13.0, *)) {
        BGAppRefreshTaskRequest *request = [[BGAppRefreshTaskRequest alloc] initWithIdentifier:self.backgroundTaskIdentifier];
        request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:15 * 60]; // 15 minutes

        NSError *error = nil;
        [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];

        if (error) {
            NSLog(@"❌ Failed to schedule BGAppRefreshTask: %@", error);
        } else {
            NSLog(@"✅ Scheduled next BGAppRefreshTask");
        }
    }
}

#pragma mark - Silent Push Notification Handler

- (void)handleSilentPushNotificationWithUserInfo:(NSDictionary *)userInfo
                                      completion:(void (^)(UIBackgroundFetchResult))completion {
    NSLog(@"🔔 Silent push notification received");

    // Check if this is an OTA update notification
    NSDictionary *otaInfo = userInfo[@"ota_update"];
    if (!otaInfo || ![otaInfo isKindOfClass:[NSDictionary class]]) {
        NSLog(@"ℹ️ Not an OTA update notification");
        completion(UIBackgroundFetchResultNoData);
        return;
    }

    NSString *version = otaInfo[@"version"];
    BOOL immediate = [otaInfo[@"immediate"] boolValue];

    NSLog(@"📦 OTA update push received for version: %@, immediate: %d", version ?: @"unknown", immediate);

    // Start background task
    [self startBackgroundTask];

    // Handle foreground vs background
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
        NSLog(@"ℹ️ App in foreground - scheduling download for later");
        // Schedule download for next background opportunity
        if (@available(iOS 13.0, *)) {
            [self scheduleAppRefreshTask];
        }
        [self endBackgroundTask];
        completion(UIBackgroundFetchResultNewData);
    } else {
        NSLog(@"⬇️ App in background - downloading update now");
        // Download immediately in background
        __weak OSBackgroundUpdateManager *weakSelf = self;
        [self downloadUpdateInBackgroundWithCompletion:^(BOOL success) {
            __strong OSBackgroundUpdateManager *strongSelf = weakSelf;
            [strongSelf endBackgroundTask];
            completion(success ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultFailed);
        }];
    }
}

#pragma mark - Private Helpers

- (void)performBackgroundUpdateCheckWithCompletion:(void (^)(UIBackgroundFetchResult))completion {
    __weak OSBackgroundUpdateManager *weakSelf = self;
    [self.otaManager checkForUpdatesWithCompletion:^(BOOL hasUpdate, NSString * _Nullable version, NSError * _Nullable error) {
        __strong OSBackgroundUpdateManager *strongSelf = weakSelf;
        if (!strongSelf) {
            completion(UIBackgroundFetchResultFailed);
            return;
        }

        if (error) {
            completion(UIBackgroundFetchResultFailed);
            return;
        }

        if (hasUpdate) {
            [strongSelf downloadUpdateInBackgroundWithCompletion:^(BOOL success) {
                completion(success ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultFailed);
            }];
        } else {
            completion(UIBackgroundFetchResultNoData);
        }
    }];
}

- (void)downloadUpdateInBackgroundWithCompletion:(void (^)(BOOL))completion {
    NSDate *startTime = [NSDate date];

    __weak OSBackgroundUpdateManager *weakSelf = self;
    [self.otaManager downloadUpdateWithProgressHandler:^(NSInteger downloaded, NSInteger total, NSInteger skipped) {
        NSLog(@"⬇️ Progress: %ld/%ld files downloaded, %ld skipped", (long)downloaded, (long)total, (long)skipped);
    } errorHandler:^(NSString * _Nonnull error) {
        NSLog(@"❌ Download error: %@", error);
    } completion:^(BOOL success) {
        __strong OSBackgroundUpdateManager *strongSelf = weakSelf;
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
        NSLog(@"⏱️ Background download completed in %.2fs, success: %d", duration, success);

        if (success) {
            // Update downloaded successfully and marked as pending swap
            // The cache swap will happen automatically when app enters foreground
            NSLog(@"✅ Update downloaded in background - pending swap on foreground");
            completion(YES);
        } else {
            completion(NO);
        }
    }];
}

#pragma mark - Background Task Management

- (void)startBackgroundTask {
    __weak OSBackgroundUpdateManager *weakSelf = self;
    self.backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        NSLog(@"⚠️ Background task expired");
        __strong OSBackgroundUpdateManager *strongSelf = weakSelf;
        [strongSelf endBackgroundTask];
    }];
}

- (void)endBackgroundTask {
    if (self.backgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:self.backgroundTask];
        self.backgroundTask = UIBackgroundTaskInvalid;
    }
}

#pragma mark - User Notifications

- (void)showUpdateAvailableNotificationWithVersion:(NSString * _Nullable)version {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"App Update Available";
    content.body = @"A new version has been downloaded and will be applied when you restart the app.";
    content.sound = [UNNotificationSound defaultSound];

    if (version) {
        content.userInfo = @{@"version": version};
    }

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"os-manual-ota-update-available"
                                                                          content:content
                                                                          trigger:nil]; // Deliver immediately

    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                           withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"❌ Failed to show notification: %@", error);
        }
    }];
}

#pragma mark - Configuration

- (void)setMinimumBackgroundFetchInterval:(NSTimeInterval)interval {
    [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:interval];
    NSLog(@"✅ Set minimum background fetch interval to %.0fs", interval);
}

- (void)enableBackgroundUpdates:(BOOL)enabled {
    if (enabled) {
        [self setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
        if (@available(iOS 13.0, *)) {
            [self scheduleAppRefreshTask];
        }
        NSLog(@"✅ Background updates enabled");
    } else {
        [self setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        if (@available(iOS 13.0, *)) {
            [[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:self.backgroundTaskIdentifier];
        }
        NSLog(@"⚠️ Background updates disabled");
    }
}

@end
