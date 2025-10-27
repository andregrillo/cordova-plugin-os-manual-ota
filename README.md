# cordova-plugin-os-manual-ota

Cordova plugin for manual control of OutSystems OTA (Over The Air) updates with Background Fetch and Silent Push Notification support.

## Features

- ✅ **Automatic OTA Blocking** - Automatically patches OutSystemsManifestLoader.js to block auto-updates
- ✅ **Manual OTA Control** - Disable automatic OTA updates and trigger them manually
- ✅ **Background Fetch** - Automatic silent updates using iOS Background Fetch
- ✅ **Silent Push Notifications** - Trigger immediate updates via push notifications
- ✅ **Incremental Updates** - Only downloads changed files (hash-based comparison)
- ✅ **Progress Tracking** - Real-time download progress callbacks
- ✅ **Automatic Rollback** - Detects crashes and rolls back automatically
- ✅ **Manual Rollback** - Rollback to previous version on demand
- ✅ **Leverages OutSystems Infrastructure** - Uses existing OSCacheResources for downloads
- ✅ **Dynamic Toggle** - Enable/disable blocking at runtime via JavaScript API

## Installation

```bash
cordova plugin add cordova-plugin-os-manual-ota
```

Or from local path:

```bash
cordova plugin add /path/to/cordova-plugin-os-manual-ota
```

**What happens on installation:**
1. Plugin files are copied to your project
2. iOS background modes are configured automatically
3. **OutSystemsManifestLoader.js is automatically patched** (via hook)
4. Automatic OTA updates can now be controlled via API

## iOS Setup

### 1. Enable Background Modes

The plugin automatically adds the required background modes to your `Info.plist`:
- `fetch` - For Background Fetch
- `remote-notification` - For Silent Push Notifications

### 2. AppDelegate Hooks - ✅ **AUTOMATIC!**

**Good news:** The plugin automatically swizzles AppDelegate methods using Objective-C runtime magic! 🎉

**No manual code changes needed!** The plugin uses method swizzling to automatically intercept:
- `application:performFetchWithCompletionHandler:` (Background Fetch)
- `application:didReceiveRemoteNotification:fetchCompletionHandler:` (Silent Push)

**How it works:**
1. `OSAppDelegateSwizzler` loads automatically when app starts
2. Finds your AppDelegate class dynamically
3. Swizzles (hooks) the background methods
4. Routes calls to the plugin's background manager

**Console output when it works:**
```
🔧 [OSManualOTA] Swizzler loading...
✅ [OSManualOTA] Found AppDelegate: AppDelegate
✅ [OSManualOTA] Background Fetch swizzled
✅ [OSManualOTA] Silent Push swizzled
✅ [OSManualOTA] AppDelegate methods swizzled successfully!
```

**If you already have these methods:** Don't worry! The swizzler detects existing implementations and chains them properly.

**Manual setup (optional):** If swizzling doesn't work for some reason, you can still add methods manually:

<details>
<summary>Click to see manual AppDelegate setup (not needed in most cases)</summary>

#### For Objective-C AppDelegate:

```objc
#import "OSBackgroundUpdateManager-Swift.h"

// Background Fetch (iOS 7+)
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [[OSBackgroundUpdateManager shared] performBackgroundFetchWithCompletion:completionHandler];
}

// Silent Push Notifications
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [[OSBackgroundUpdateManager shared] handleSilentPushNotificationWithUserInfo:userInfo completion:completionHandler];
}
```

#### For Swift AppDelegate:

```swift
import UIKit

func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    OSBackgroundUpdateManager.shared.performBackgroundFetch(completion: completionHandler)
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    OSBackgroundUpdateManager.shared.handleSilentPushNotification(userInfo: userInfo, completion: completionHandler)
}
```

</details>

### 3. Configure Plugin

Add configuration to your `config.xml`:

```xml
<preference name="OSManualOTABaseURL" value="https://yourenv.outsystems.net/YourApp" />
<preference name="OSManualOTAHostname" value="yourenv.outsystems.net" />
<preference name="OSManualOTAApplicationPath" value="/YourApp" />
```

Or configure programmatically (see usage below).

## Usage

### Basic Configuration

```javascript
document.addEventListener('deviceready', function() {
    // Configure the plugin with your OutSystems environment
    OSManualOTA.configure({
        baseURL: 'https://yourenv.outsystems.net/YourApp',
        hostname: 'yourenv.outsystems.net',
        applicationPath: '/YourApp'
    },
    function() {
        console.log('OTA configured successfully');
    },
    function(error) {
        console.error('OTA configuration failed:', error);
    });

    // Enable automatic OTA blocking
    OSManualOTA.setOTABlockingEnabled(true,
        function() {
            console.log('Automatic OTA is now blocked');
        },
        function(error) {
            console.error('Failed to enable OTA blocking:', error);
        }
    );
}, false);
```

### Check for Updates

```javascript
OSManualOTA.checkForUpdates(
    function(result) {
        if (result.hasUpdate) {
            console.log('Update available:', result.version);
            // Proceed with download
        } else {
            console.log('App is up to date');
        }
    },
    function(error) {
        console.error('Failed to check for updates:', error);
    }
);
```

### Download Update with Progress

```javascript
OSManualOTA.downloadUpdate(
    // Progress callback
    function(progress) {
        console.log('Download progress:', progress.percentage + '%');
        console.log('Files:', progress.downloaded + '/' + progress.total);
        console.log('Skipped:', progress.skipped);

        // Update UI
        updateProgressBar(progress.percentage);
    },
    // Error callback
    function(error) {
        console.error('Download failed:', error);
    },
    // Complete callback
    function(result) {
        if (result.success) {
            console.log('Download completed successfully');
            // Apply the update
        } else {
            console.error('Download failed');
        }
    }
);
```

### Apply Update

```javascript
OSManualOTA.applyUpdate(
    function(result) {
        console.log(result.message);
        // Show message to user: "Update will be applied on next app restart"
        showRestartPrompt();
    },
    function(error) {
        console.error('Failed to apply update:', error);
    }
);
```

### Check, Download, and Apply (Convenience Method)

```javascript
OSManualOTA.checkDownloadAndApply(
    // Progress callback
    function(progress) {
        updateProgressBar(progress.percentage);
    },
    // Success callback
    function(result) {
        if (result.applied) {
            console.log('Update downloaded and will be applied on restart');
            showRestartPrompt();
        } else if (result.hasUpdate === false) {
            console.log('No update available');
        }
    },
    // Error callback
    function(error) {
        console.error('Update process failed:', error);
    }
);
```

### Rollback to Previous Version

```javascript
OSManualOTA.rollback(
    function(result) {
        console.log('Rolled back successfully');
        // Restart app
        window.location.reload();
    },
    function(error) {
        console.error('Rollback failed:', error);
    }
);
```

### Get Version Information

```javascript
OSManualOTA.getVersionInfo(
    function(info) {
        console.log('Current version:', info.currentVersion);
        console.log('Downloaded version:', info.downloadedVersion);
        console.log('Previous version:', info.previousVersion);
        console.log('Is update downloaded:', info.isUpdateDownloaded);
        console.log('Is downloading:', info.isDownloading);
    },
    function(error) {
        console.error('Failed to get version info:', error);
    }
);
```

### Cancel Download

```javascript
OSManualOTA.cancelDownload(
    function() {
        console.log('Download cancelled');
    },
    function(error) {
        console.error('Failed to cancel:', error);
    }
);
```

## Background Updates

### Enable Background Fetch

```javascript
// Enable background updates
OSManualOTA.enableBackgroundUpdates(true,
    function() {
        console.log('Background updates enabled');
    },
    function(error) {
        console.error('Failed to enable background updates:', error);
    }
);

// Set custom fetch interval (in seconds)
OSManualOTA.setBackgroundFetchInterval(3600, // 1 hour
    function() {
        console.log('Background fetch interval set');
    },
    function(error) {
        console.error('Failed to set interval:', error);
    }
);
```

### Test Background Fetch in Xcode

1. Run your app in Xcode
2. Go to **Debug → Simulate Background Fetch**
3. Check the console for background update logs

### Silent Push Notifications

To trigger an immediate update via silent push, send a push notification with this payload:

```json
{
  "aps": {
    "content-available": 1
  },
  "ota_update": {
    "version": "1.2.3",
    "immediate": true
  }
}
```

**Important:** Silent push notifications do **not** require user permission!

## Events

### Listen for OTA Blocking Status Changes

```javascript
OSManualOTA.onBlockingStatusChanged(function(event) {
    console.log('OTA blocking enabled:', event.enabled);
});
```

## Complete Example

```javascript
document.addEventListener('deviceready', function() {

    // 1. Configure
    OSManualOTA.configure({
        baseURL: 'https://myenv.outsystems.net/MyApp',
        hostname: 'myenv.outsystems.net',
        applicationPath: '/MyApp'
    }, function() {
        console.log('✅ Configured');

        // 2. Enable OTA blocking
        OSManualOTA.setOTABlockingEnabled(true);

        // 3. Enable background updates
        OSManualOTA.enableBackgroundUpdates(true);

        // 4. Check for updates on app start
        checkForUpdatesWithUI();

    }, function(error) {
        console.error('❌ Configuration failed:', error);
    });

}, false);

function checkForUpdatesWithUI() {
    showLoadingSpinner();

    OSManualOTA.checkForUpdates(
        function(result) {
            hideLoadingSpinner();

            if (result.hasUpdate) {
                showUpdateDialog(result.version);
            }
        },
        function(error) {
            hideLoadingSpinner();
            console.error('Check failed:', error);
        }
    );
}

function showUpdateDialog(version) {
    // Show native dialog or custom UI
    var download = confirm('Update available (' + version + '). Download now?');

    if (download) {
        downloadUpdateWithUI();
    }
}

function downloadUpdateWithUI() {
    showProgressDialog();

    OSManualOTA.downloadUpdate(
        // Progress
        function(progress) {
            updateProgressDialog(progress.percentage);
        },
        // Error
        function(error) {
            hideProgressDialog();
            alert('Download failed: ' + error);
        },
        // Complete
        function(result) {
            hideProgressDialog();

            if (result.success) {
                // Apply update
                OSManualOTA.applyUpdate(
                    function() {
                        var restart = confirm('Update downloaded. Restart app to apply?');
                        if (restart) {
                            window.location.reload();
                        }
                    },
                    function(error) {
                        alert('Failed to apply: ' + error);
                    }
                );
            }
        }
    );
}
```

## API Reference

### Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| `configure()` | config, successCallback, errorCallback | Configure plugin with environment details |
| `checkForUpdates()` | successCallback, errorCallback | Check if update is available |
| `downloadUpdate()` | progressCallback, errorCallback, completeCallback | Download available update |
| `applyUpdate()` | successCallback, errorCallback | Apply downloaded update (takes effect on restart) |
| `rollback()` | successCallback, errorCallback | Rollback to previous version |
| `cancelDownload()` | successCallback, errorCallback | Cancel ongoing download |
| `getVersionInfo()` | successCallback, errorCallback | Get current version information |
| `setOTABlockingEnabled()` | enabled, successCallback, errorCallback | Enable/disable automatic OTA blocking |
| `isOTABlockingEnabled()` | successCallback, errorCallback | Check if OTA blocking is enabled |
| `enableBackgroundUpdates()` | enabled, successCallback, errorCallback | Enable/disable background updates |
| `setBackgroundFetchInterval()` | interval, successCallback, errorCallback | Set background fetch interval (seconds) |
| `checkAndDownload()` | progressCallback, successCallback, errorCallback | Convenience: check and download if available |
| `checkDownloadAndApply()` | progressCallback, successCallback, errorCallback | Convenience: full update flow |

## How It Works

### Automatic OTA Blocking

When `setOTABlockingEnabled(true)` is called:
1. Plugin intercepts OutSystems manifest loader
2. Blocks automatic version checks at app startup
3. App launches with current cached version
4. Updates only happen when you trigger them manually

### Background Fetch Flow

```
iOS triggers background fetch (every 15min-1hr)
    ↓
Plugin checks for updates
    ↓
If update available → Download silently
    ↓
Apply automatically (takes effect on next launch)
    ↓
Optional: Show notification to user
```

### Incremental Updates

The plugin uses hash-based comparison (like your bash script):
1. Fetch new manifest with file hashes
2. Compare with locally stored hashes
3. Download only changed files
4. Much faster than full download!

### Automatic Rollback

If app crashes after an update:
1. Plugin detects crash flag on next launch
2. Automatically rolls back to previous version
3. App launches with stable version
4. Crash is logged for investigation

## Troubleshooting

### Background Fetch Not Working

1. Check that Background Modes are enabled in capabilities
2. Verify `UIBackgroundModes` in Info.plist
3. Test with "Simulate Background Fetch" in Xcode
4. Check that `setMinimumBackgroundFetchInterval` is not set to `UIApplicationBackgroundFetchIntervalNever`

### Silent Push Not Working

1. Verify push notification payload includes `"content-available": 1`
2. Ensure `remote-notification` is in Background Modes
3. Check device is not in Low Power Mode
4. Verify APNS certificate is valid

### Updates Not Downloading

1. Check network connectivity
2. Verify configuration URLs are correct
3. Check console logs for error messages
4. Ensure OutSystems environment is accessible

### App Not Using Updated Version

1. Verify `applyUpdate()` was called successfully
2. Restart the app (updates take effect on restart)
3. Check version info with `getVersionInfo()`

## TODO / Future Improvements

- [ ] Integrate fully with OutSystems `OSCacheResources` (currently placeholder)
- [ ] Add WiFi-only download option
- [ ] Add download size estimation before download
- [ ] Add analytics integration
- [ ] Add Android support
- [ ] Add retry logic for failed downloads
- [ ] Add delta patching for even faster updates

## Contributing

Contributions are welcome! Please:
1. Test thoroughly on real devices
2. Add unit tests if possible
3. Update documentation
4. Follow Swift/JavaScript style guidelines

## License

MIT License - See LICENSE file for details

## Author

Andre Grillo - OutSystems Native Development Team

## Support

For issues, questions, or feature requests, please open an issue on GitHub.
