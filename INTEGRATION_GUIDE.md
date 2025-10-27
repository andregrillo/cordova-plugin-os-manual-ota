# Integration Guide for cordova-plugin-os-manual-ota

This guide will walk you through integrating the Manual OTA plugin into your OutSystems mobile app.

## Prerequisites

- OutSystems mobile app built with MABS
- Xcode 14+ (for iOS)
- CocoaPods installed
- Access to your OutSystems environment

## Step 1: Install the Plugin

### Option A: Install from Local Path

```bash
cd /path/to/your/cordova/project
cordova plugin add /path/to/cordova-plugin-os-manual-ota
```

### Option B: Install from Git (once published)

```bash
cordova plugin add cordova-plugin-os-manual-ota
```

## Step 2: Add Swift Support Hook

Since this plugin uses Swift, you'll need a hook to set the Swift version. Create a file at `hooks/after_prepare/swift_support.js`:

```javascript
#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    if (context.opts.platforms.indexOf('ios') === -1) {
        return;
    }

    const platformPath = path.join(context.opts.projectRoot, 'platforms', 'ios');
    const projectFiles = fs.readdirSync(platformPath).filter(f => f.endsWith('.xcodeproj'));

    if (projectFiles.length === 0) return;

    const projectName = projectFiles[0].replace('.xcodeproj', '');
    const pbxprojPath = path.join(platformPath, projectFiles[0], 'project.pbxproj');

    let pbxproj = fs.readFileSync(pbxprojPath, 'utf8');

    // Set Swift version
    if (pbxproj.indexOf('SWIFT_VERSION') === -1) {
        pbxproj = pbxproj.replace(
            /PRODUCT_NAME = ".*";/g,
            '$&\n\t\t\t\tSWIFT_VERSION = 5.0;'
        );
    }

    // Enable Swift
    pbxproj = pbxproj.replace(
        /ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = NO;/g,
        'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;'
    );

    fs.writeFileSync(pbxprojPath, pbxproj, 'utf8');
    console.log('✅ Swift support configured');
};
```

Make it executable:

```bash
chmod +x hooks/after_prepare/swift_support.js
```

## Step 3: AppDelegate - ✅ **AUTOMATIC!**

**Great news!** You **don't need to modify AppDelegate** manually! 🎉

The plugin uses **Objective-C method swizzling** to automatically hook into AppDelegate methods at runtime.

### What Gets Swizzled Automatically

When your app starts, `OSAppDelegateSwizzler` automatically hooks:

1. ✅ `application:performFetchWithCompletionHandler:` (Background Fetch)
2. ✅ `application:didReceiveRemoteNotification:fetchCompletionHandler:` (Silent Push)

### Verify Swizzling Works

After installing the plugin, run your app and check the console:

```
🔧 [OSManualOTA] Swizzler loading...
✅ [OSManualOTA] Found AppDelegate: AppDelegate
ℹ️  [OSManualOTA] performFetchWithCompletionHandler not found, adding it
✅ [OSManualOTA] Background Fetch swizzled
ℹ️  [OSManualOTA] didReceiveRemoteNotification not found, adding it
✅ [OSManualOTA] Silent Push swizzled
✅ [OSManualOTA] AppDelegate methods swizzled successfully!
```

If you see these logs, **swizzling worked!** Background operations are now automatic.

### How It Works

The swizzler:
1. Loads automatically via `+load` method
2. Finds your AppDelegate class dynamically
3. Checks if background methods exist
4. If they don't exist → Adds them
5. If they exist → Swaps implementations
6. Routes all calls to `OSBackgroundUpdateManager`

**See [SWIZZLING_GUIDE.md](SWIZZLING_GUIDE.md) for technical details.**

### Manual Setup (Fallback)

**Only if swizzling fails** (rare), you can add methods manually:

<details>
<summary>Click to see manual AppDelegate setup (not needed in most cases)</summary>

#### Locate AppDelegate

Your AppDelegate is located at:
```
platforms/ios/YourApp/Classes/AppDelegate.m
```

#### Add Import at Top of File

```objc
#import "OSBackgroundUpdateManager-Swift.h"
```

#### Add Background Fetch Method

```objc
- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    NSLog(@"🔄 Background Fetch triggered");
    [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];
}
```

#### Add Silent Push Handler

```objc
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    NSLog(@"🔔 Silent push received: %@", userInfo);
    [[OSBackgroundUpdateManager shared] handleSilentPushNotificationWithUserInfo:userInfo
                                                                       completion:completionHandler];
}
```

</details>

## Step 4: Configure in Your OutSystems App

### Option A: Configure via config.xml

Add to your `config.xml`:

```xml
<platform name="ios">
    <preference name="OSManualOTABaseURL" value="https://yourenv.outsystems.net/YourApp" />
    <preference name="OSManualOTAHostname" value="yourenv.outsystems.net" />
    <preference name="OSManualOTAApplicationPath" value="/YourApp" />
</platform>
```

### Option B: Configure Programmatically in JavaScript

In your OutSystems app's JavaScript code (e.g., in an OnReady event):

```javascript
document.addEventListener('deviceready', function() {
    // Configure OTA
    OSManualOTA.configure({
        baseURL: 'https://yourenv.outsystems.net/YourApp',
        hostname: 'yourenv.outsystems.net',
        applicationPath: '/YourApp'
    },
    function() {
        console.log('✅ OTA configured');

        // Enable OTA blocking
        OSManualOTA.setOTABlockingEnabled(true);

        // Enable background updates
        OSManualOTA.enableBackgroundUpdates(true);
    },
    function(error) {
        console.error('❌ OTA config failed:', error);
    });
}, false);
```

## Step 5: Block Automatic OTA (Patch OutSystemsManifestLoader.js)

To completely block the automatic OTA at startup, you need to patch `OutSystemsManifestLoader.js`.

### Locate the File

```
www/scripts/OutSystemsManifestLoader.js
platforms/ios/www/scripts/OutSystemsManifestLoader.js
```

### Add Hook at the Beginning

Since the file is minified, you'll need to add a hook. Create a hook script that patches it after build:

```javascript
// hooks/after_prepare/patch_ota_loader.js

#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    const platformPath = path.join(context.opts.projectRoot, 'platforms', 'ios', 'www', 'scripts');
    const loaderPath = path.join(platformPath, 'OutSystemsManifestLoader.js');

    if (!fs.existsSync(loaderPath)) {
        console.log('⚠️ OutSystemsManifestLoader.js not found');
        return;
    }

    let content = fs.readFileSync(loaderPath, 'utf8');

    // Add blocking check at the top
    const hookCode = `
// OSManualOTA Plugin Hook
(function() {
    var originalGetLatestVersion = window.OSManifestLoader && window.OSManifestLoader.getLatestVersion;
    var originalGetLatestManifest = window.OSManifestLoader && window.OSManifestLoader.getLatestManifest;

    if (originalGetLatestVersion) {
        window.OSManifestLoader.getLatestVersion = function() {
            if (window.OSManualOTA && window.OSManualOTA.__blockingEnabled) {
                console.log('[OSManualOTA] Blocking automatic version check');
                return Promise.resolve({versionToken: window.OSManualOTA.__currentVersion || 'unknown'});
            }
            return originalGetLatestVersion.apply(this, arguments);
        };
    }

    if (originalGetLatestManifest) {
        window.OSManualOTA.getLatestManifest = function() {
            if (window.OSManualOTA && window.OSManualOTA.__blockingEnabled) {
                console.log('[OSManualOTA] Blocking automatic manifest fetch');
                return Promise.resolve({manifest: {urlVersions: {}, versionToken: 'blocked'}});
            }
            return originalGetLatestManifest.apply(this, arguments);
        };
    }
})();
`;

    if (content.indexOf('OSManualOTA Plugin Hook') === -1) {
        content = hookCode + '\n' + content;
        fs.writeFileSync(loaderPath, content, 'utf8');
        console.log('✅ OutSystemsManifestLoader.js patched for manual OTA');
    }
};
```

Make it executable:

```bash
chmod +x hooks/after_prepare/patch_ota_loader.js
```

## Step 6: Create Update UI in OutSystems

### Create a Screen for Manual Updates

In OutSystems Service Studio:

1. Create a new Screen called "AppUpdate"
2. Add these UI elements:
   - Label: "Current Version: {CurrentVersionVar}"
   - Button: "Check for Updates"
   - ProgressBar (initially hidden)
   - Label: "Download Progress: {ProgressVar}%"
   - Button: "Apply Update" (initially disabled)

3. Add these Client Actions:

#### CheckForUpdates Action

```javascript
// JavaScript node
OSManualOTA.checkForUpdates(
    function(result) {
        if (result.hasUpdate) {
            $parameters.HasUpdate = true;
            $parameters.NewVersion = result.version;
            $resolve();
        } else {
            $parameters.HasUpdate = false;
            $resolve();
        }
    },
    function(error) {
        $parameters.Error = error;
        $reject(error);
    }
);
```

#### DownloadUpdate Action

```javascript
// JavaScript node
var progressCallback = function(progress) {
    // Update progress bar
    $parameters.Progress = progress.percentage;
    // Trigger reactive update in OutSystems
    window.dispatchEvent(new CustomEvent('updateProgress', {detail: progress}));
};

var errorCallback = function(error) {
    $parameters.Error = error;
    $reject(error);
};

var completeCallback = function(result) {
    if (result.success) {
        $parameters.Success = true;
        $resolve();
    } else {
        $reject('Download failed');
    }
};

OSManualOTA.downloadUpdate(progressCallback, errorCallback, completeCallback);
```

#### ApplyUpdate Action

```javascript
// JavaScript node
OSManualOTA.applyUpdate(
    function(result) {
        $parameters.Success = true;
        $parameters.Message = result.message;
        $resolve();
    },
    function(error) {
        $parameters.Error = error;
        $reject(error);
    }
);
```

## Step 7: Enable Silent Push Notifications (Optional)

### Backend Configuration

To send silent push notifications when updates are available:

1. **Set up APNS** - Configure Apple Push Notification Service
2. **Get device tokens** - Collect device tokens from users
3. **Send silent push** when update is published:

```bash
curl -X POST "https://api.push.apple.com/3/device/{device_token}" \
  -H "authorization: bearer {your_apns_token}" \
  -H "apns-topic: com.yourapp.bundle" \
  -H "apns-priority: 5" \
  -H "apns-push-type: background" \
  -d '{
    "aps": {
      "content-available": 1
    },
    "ota_update": {
      "version": "1.2.3",
      "immediate": true
    }
  }'
```

## Step 8: Testing

### Test in Xcode Simulator

1. Build and run in Xcode
2. Test Background Fetch:
   - Go to **Debug → Simulate Background Fetch**
   - Check console for logs

### Test on Real Device

1. Install app on device
2. Close app (swipe up to kill)
3. Wait for background fetch (can take 15min-1hr)
4. Or send a silent push notification

### Test Manual Update Flow

1. Make a change in OutSystems (e.g., change text on a screen)
2. Publish to development environment
3. Open app
4. Click "Check for Updates"
5. Should detect new version
6. Click "Download"
7. Watch progress bar
8. Click "Apply"
9. Restart app
10. Should see your changes

## Step 9: Monitor and Debug

### Enable Logging

All plugin methods log to console. View logs in:
- **Xcode**: View → Debug Area → Activate Console
- **Device Console**: Window → Devices and Simulators → Select device → Open Console

### Check Version Info

```javascript
OSManualOTA.getVersionInfo(function(info) {
    console.log(JSON.stringify(info, null, 2));
});
```

### Force Rollback Test

To test automatic rollback on crash:

```javascript
// Simulate crash after update
OSManualOTA.applyUpdate(function() {
    // Force crash (for testing only!)
    setTimeout(function() {
        throw new Error('Simulated crash');
    }, 1000);
}, function(error) {
    console.error(error);
});
```

On next launch, plugin should detect crash and rollback automatically.

## Troubleshooting

### Plugin Not Found Error

**Error:** `Cannot find module 'OSManualOTA'`

**Solution:**
1. Verify plugin is installed: `cordova plugin list`
2. Remove and re-add: `cordova plugin remove cordova-plugin-os-manual-ota && cordova plugin add cordova-plugin-os-manual-ota`
3. Clean and rebuild: `cordova clean ios && cordova build ios`

### Swift Compilation Errors

**Error:** Swift version mismatch or bridging header not found

**Solution:**
1. Open project in Xcode
2. Go to Build Settings
3. Set Swift Language Version to 5.0
4. Verify bridging header path: `$(PROJECT_DIR)/$(PROJECT_NAME)/Plugins/cordova-plugin-os-manual-ota/OSManualOTA-Bridging-Header.h`

### Background Fetch Not Working

**Issue:** Background updates never trigger

**Solution:**
1. Verify Background Modes are enabled in Xcode
2. Check `Info.plist` contains `UIBackgroundModes` array with `fetch` and `remote-notification`
3. Ensure `setMinimumBackgroundFetchInterval` is called
4. Test with "Simulate Background Fetch" in Xcode
5. On real device, wait at least 30 minutes

### OutSystems Cache Not Swapping

**Issue:** Updated files downloaded but app still shows old version

**Solution:**
1. Verify `applyUpdate()` was called successfully
2. **Restart the app** (updates take effect on restart)
3. Check version info to confirm downloaded version matches current
4. Clear app data and reinstall if issue persists

## Production Checklist

Before going to production:

- [ ] Test manual update flow thoroughly
- [ ] Test background fetch on real devices
- [ ] Test silent push notifications
- [ ] Test automatic rollback after crash
- [ ] Test manual rollback
- [ ] Configure proper update check intervals
- [ ] Set up backend push notification infrastructure (if using silent push)
- [ ] Add analytics/monitoring for update metrics
- [ ] Add user-facing update UI
- [ ] Test on slow/unstable networks
- [ ] Test with large update sizes
- [ ] Document rollback procedures for support team

## Next Steps

1. Implement OutSystems integration with OSCacheResources (currently placeholder)
2. Add WiFi-only download option
3. Add update size estimation
4. Add analytics integration
5. Consider adding Android support

## Support

For issues or questions:
- Check the [README](README.md)
- Review the [API documentation](README.md#api-reference)
- Open an issue on GitHub
- Contact OutSystems support

---

**Happy updating! 🚀**
