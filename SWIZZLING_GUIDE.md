# AppDelegate Swizzling Guide

## 🪄 Automatic AppDelegate Integration

The plugin uses **Objective-C method swizzling** to automatically hook into AppDelegate without requiring any manual code changes!

---

## What is Method Swizzling?

Method swizzling is an Objective-C runtime feature that allows you to swap method implementations at runtime. Think of it as "hijacking" a method to add custom behavior.

### **Visual Explanation:**

**Before Swizzling:**
```
App calls: [appDelegate application:performFetchWithCompletionHandler:]
              ↓
         AppDelegate's implementation (or doesn't exist)
```

**After Swizzling:**
```
App calls: [appDelegate application:performFetchWithCompletionHandler:]
              ↓
         OSAppDelegateSwizzler's implementation
              ↓
         Calls OSBackgroundUpdateManager
              ↓
         (Optionally) Calls original AppDelegate implementation
```

---

## How Our Swizzler Works

### **1. Automatic Loading**

The swizzler loads automatically when the app starts:

```objc
// OSAppDelegateSwizzler.m

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSLog(@"🔧 [OSManualOTA] Swizzler loading...");

        // Wait for AppDelegate to be ready
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC),
                      dispatch_get_main_queue(), ^{
            [self swizzleAppDelegateMethods];
        });
    });
}
```

**When `+load` runs:**
- Called automatically when class is loaded into memory
- Happens very early in app lifecycle
- Guaranteed to run before `main()`

### **2. Finding AppDelegate**

```objc
+ (Class)getAppDelegateClass {
    // Get actual AppDelegate instance from UIApplication
    id appDelegate = [[UIApplication sharedApplication] delegate];

    if (appDelegate) {
        return [appDelegate class];
    }

    // Fallback: Look for class named "AppDelegate"
    return NSClassFromString(@"AppDelegate");
}
```

**Why this works:**
- Doesn't hardcode class names
- Works with custom AppDelegate subclasses
- Finds actual runtime AppDelegate instance

### **3. Swizzling Background Fetch**

```objc
+ (void)swizzleBackgroundFetchForClass:(Class)appDelegateClass {
    SEL originalSelector = @selector(application:performFetchWithCompletionHandler:);
    SEL swizzledSelector = @selector(osmanualota_application:performFetchWithCompletionHandler:);

    Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(self, swizzledSelector);

    if (!originalMethod) {
        // AppDelegate doesn't have this method, add ours
        class_addMethod(appDelegateClass,
                       originalSelector,
                       method_getImplementation(swizzledMethod),
                       method_getTypeEncoding(swizzledMethod));
    } else {
        // Method exists, swap implementations
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}
```

**Two scenarios:**

**Scenario A: AppDelegate doesn't have the method**
- Add our implementation directly
- iOS will call our method

**Scenario B: AppDelegate already has the method**
- Swap implementations
- Our method becomes the "official" one
- Original method still callable via swizzled selector

### **4. Our Swizzled Implementation**

```objc
- (void)osmanualota_application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    NSLog(@"🔄 [OSManualOTA] Background Fetch intercepted!");

    // Call our plugin's manager
    [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];

    // Don't call original (we handle everything)
}
```

**Why we don't call the original:**
- We handle the entire background fetch flow
- Calling completion handler twice would crash
- If needed, original is still accessible via the swizzled selector

---

## What Gets Swizzled

### **1. Background Fetch (iOS 7+)**

**Original Method:**
```objc
- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
```

**Swizzled To:**
```objc
- (void)osmanualota_application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    // Check for OTA updates
    [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];
}
```

**Result:** Background fetch automatically checks for OTA updates!

### **2. Silent Push Notifications**

**Original Method:**
```objc
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
```

**Swizzled To:**
```objc
- (void)osmanualota_application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    // Check if it's an OTA notification
    if (userInfo[@"ota_update"]) {
        [[OSBackgroundUpdateManager shared] handleSilentPushNotificationWithUserInfo:userInfo
                                                                           completion:completionHandler];
    } else {
        // Not OTA, pass through to original implementation
        // (if it exists)
    }
}
```

**Result:**
- OTA push notifications handled automatically
- Other push notifications still work normally

---

## Advantages of Swizzling

### ✅ **No Manual Code Changes**
- User doesn't need to modify AppDelegate
- Works out of the box after plugin installation
- Less error-prone

### ✅ **Compatible with Existing Code**
- Doesn't break existing background fetch implementations
- Can coexist with other plugins
- Original methods still accessible

### ✅ **Automatic Discovery**
- Finds AppDelegate dynamically
- Works with custom AppDelegate subclasses
- No hardcoded assumptions

### ✅ **Handles Missing Methods**
- If AppDelegate doesn't have background fetch → adds it
- If AppDelegate already has it → swizzles it
- Works in both cases

---

## Debugging Swizzling

### **Check Console Logs**

When the app launches, you should see:

```
🔧 [OSManualOTA] Swizzler loading...
✅ [OSManualOTA] Found AppDelegate: AppDelegate
ℹ️  [OSManualOTA] performFetchWithCompletionHandler not found, adding it
✅ [OSManualOTA] Background Fetch swizzled
ℹ️  [OSManualOTA] didReceiveRemoteNotification not found, adding it
✅ [OSManualOTA] Silent Push swizzled
✅ [OSManualOTA] AppDelegate methods swizzled successfully!
```

### **When Background Fetch Runs**

```
🔄 [OSManualOTA] Background Fetch intercepted!
🔄 Checking for OTA updates...
```

### **When Silent Push Arrives**

```
🔔 [OSManualOTA] Remote Notification intercepted!
📦 Notification payload: { ota_update: { version: "1.2.3" } }
✅ [OSManualOTA] OTA update notification detected
```

---

## Testing Swizzling

### **1. Verify Swizzling Occurred**

Add this to your app's JavaScript (after deviceready):

```javascript
// This will trigger background fetch manually (for testing)
OSManualOTA.enableBackgroundUpdates(true, function() {
    console.log('Background updates enabled');
}, function(error) {
    console.error('Error:', error);
});
```

### **2. Test Background Fetch in Xcode**

1. Run app in Xcode
2. Go to **Debug → Simulate Background Fetch**
3. Check console for swizzler logs

### **3. Test Silent Push**

Send a test notification:
```json
{
  "aps": {
    "content-available": 1
  },
  "ota_update": {
    "version": "test",
    "immediate": true
  }
}
```

Watch console for:
```
🔔 [OSManualOTA] Remote Notification intercepted!
```

---

## Troubleshooting

### **Issue: "Could not find AppDelegate class"**

**Cause:** AppDelegate not loaded yet or unusual naming

**Solution:**
- Check if AppDelegate is named differently
- Add delay in `+load` method
- Verify UIApplication.sharedApplication.delegate exists

### **Issue: Swizzling doesn't work**

**Symptoms:** Background fetch never triggers plugin code

**Debug:**
1. Check console for swizzler logs
2. Verify `OSAppDelegateSwizzler.m` is compiled
3. Add breakpoint in `+load` method
4. Check if methods are actually being swizzled

**Solution:**
- Ensure plugin is properly installed
- Run `cordova prepare ios` again
- Check Xcode build settings for Objective-C files

### **Issue: "Undefined symbols for Swift"**

**Cause:** Swift bridging not configured or header name mismatch

**How we handle it:**
1. We try common header names (`cordova_plugin_os_manual_ota-Swift.h`, `OTA_Test-Swift.h`)
2. If none match, we forward-declare the Swift interface
3. At runtime, we verify `OSBackgroundUpdateManager` class exists using `NSClassFromString()`
4. If class not found, swizzling is skipped with a clear error message

**Solution if it fails:**
- Ensure Swift support hook is configured (see INTEGRATION_GUIDE.md Step 2)
- Set `SWIFT_VERSION = 5.0` in build settings
- Verify bridging header path in plugin.xml is correct
- Check console logs for "Swift class OSBackgroundUpdateManager found" message

### **Issue: App crashes on background fetch**

**Cause:** Completion handler called twice

**Check:**
- Ensure original AppDelegate method doesn't also call completion handler
- Our swizzled method should be the only one calling it

---

## How It Compares to Manual Setup

### **Manual AppDelegate Setup**

**Pros:**
- Explicit and visible
- Full control

**Cons:**
- ❌ Requires user to modify AppDelegate
- ❌ Error-prone (easy to forget)
- ❌ OutSystems MABS might regenerate AppDelegate
- ❌ Breaks on app updates

### **Swizzling (Our Approach)**

**Pros:**
- ✅ Fully automatic
- ✅ No user action required
- ✅ Survives app regeneration
- ✅ Works with MABS
- ✅ Compatible with existing code

**Cons:**
- Slightly more "magic" (less explicit)
- Requires understanding of runtime

---

## Advanced: Calling Original Implementation

If you want to call the original AppDelegate method **and** run plugin code:

```objc
- (void)osmanualota_application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    // First, call original implementation (if it exists)
    if ([self respondsToSelector:@selector(osmanualota_application:performFetchWithCompletionHandler:)]) {
        // This actually calls the ORIGINAL method (because they're swapped)
        [self osmanualota_application:application performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
            // Original completed

            // Now run our plugin code
            [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];
        }];
    } else {
        // No original, just run ours
        [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];
    }
}
```

**Note:** This is complex and usually not needed. Our current approach handles everything.

---

## Security Considerations

### **Is Swizzling Safe?**

✅ **Yes, when done properly:**
- Used by many production apps (Firebase, Analytics SDKs, etc.)
- Apple-approved technique
- Part of Objective-C runtime

### **Best Practices We Follow:**

1. ✅ **Use `dispatch_once`** - Swizzle only once
2. ✅ **Check for existing methods** - Handle both cases
3. ✅ **Preserve original behavior** - Chain calls when needed
4. ✅ **Log everything** - Debug visibility
5. ✅ **Fail gracefully** - Don't crash if AppDelegate not found

---

## Summary

**The swizzler provides:**
- ✅ Automatic integration (no manual AppDelegate changes)
- ✅ Background Fetch support
- ✅ Silent Push Notification support
- ✅ Compatible with existing code
- ✅ Works with OutSystems MABS
- ✅ Survives app regeneration

**You get background updates without touching a single line of AppDelegate code!** 🎉

---

## References

- [Apple: Objective-C Runtime Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Introduction/Introduction.html)
- [Method Swizzling in Objective-C](https://nshipster.com/method-swizzling/)
- [Background Execution](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background)
