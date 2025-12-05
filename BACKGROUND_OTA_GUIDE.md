# Background OTA Updates - Implementation Guide

## Overview

The plugin includes **automatic background OTA checking and downloading** using iOS Background Fetch and BGTaskScheduler. When enabled, iOS will periodically wake up your app in the background to check for and download OTA updates automatically.

## How It Works

### iOS Background Modes

The plugin uses two iOS background mechanisms:

1. **Background Fetch (iOS 7-12)**: Legacy background fetch API
2. **BGTaskScheduler (iOS 13+)**: Modern Background App Refresh Task

iOS controls **when and how often** your app runs in the background based on:
- User usage patterns (apps used frequently get more background time)
- Device battery level
- Network conditions
- System resources

**Important**: You **cannot** force exact intervals. iOS decides when to wake your app.

---

## Configuration

### 1. Plugin Installation

The plugin automatically configures the necessary capabilities in `Info.plist`:

```xml
<!-- Already configured by plugin.xml -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.outsystems.manual-ota.refresh</string>
</array>
```

### 2. Enable Background Updates

#### JavaScript API

```javascript
// Enable background updates
OSManualOTA.enableBackgroundUpdates(
    true, // enabled
    function(result) {
        console.log('Background updates enabled:', result);
    },
    function(error) {
        console.error('Failed to enable background updates:', error);
    }
);

// Set minimum fetch interval (iOS 7-12 only)
// Note: iOS 13+ uses BGTaskScheduler with 15-minute minimum
OSManualOTA.setBackgroundFetchInterval(
    3600, // seconds (1 hour)
    function(result) {
        console.log('Fetch interval set:', result);
    },
    function(error) {
        console.error('Failed to set fetch interval:', error);
    }
);

// Disable background updates
OSManualOTA.enableBackgroundUpdates(
    false,
    function(result) {
        console.log('Background updates disabled:', result);
    },
    function(error) {
        console.error('Failed to disable:', error);
    }
);
```

---

## Background Update Flow

### 1. iOS Wakes App in Background

iOS calls one of:
- `application:performFetchWithCompletionHandler:` (iOS 7-12)
- `BGAppRefreshTask` (iOS 13+)

### 2. Plugin Checks for Updates

```
OSBackgroundUpdateManager.performBackgroundFetch()
    ↓
OSManualOTAManager.checkForUpdates()
    ↓
Compares current version with server version
```

### 3. If Update Available

```
Download update in background
    ↓
Register cache frame
    ↓
Swap cache immediately
    ↓
Call switchToVersion()
    ↓
Show notification (optional)
```

### 4. Next App Launch

- User sees new version automatically
- No redundant download by automatic OTA ✅

---

## Testing Background Fetch

### Method 1: Xcode Simulator (iOS 13+)

1. Build and run app in Xcode
2. Enable background updates in your app
3. Put app in background (Home button)
4. In Xcode: **Debug → Simulate Background Fetch**
5. Check console for background update logs

### Method 2: Command Line (iOS 13+)

```bash
# Trigger BGAppRefreshTask
xcrun simctl launch booted your.bundle.id --BackgroundFetch com.outsystems.manual-ota.refresh

# Alternative: Trigger background fetch
xcrun simctl launch booted your.bundle.id --BackgroundFetch
```

### Method 3: Device Testing

**Real device testing is recommended** as simulators don't accurately reflect iOS background behavior.

1. Build app to device
2. Enable background updates
3. Use app normally for a few days
4. iOS will schedule background fetches based on usage patterns
5. Check device logs via Console.app on Mac

### Debugging on Device

```bash
# View device logs on Mac
# 1. Connect device via USB
# 2. Open Console.app
# 3. Filter by "[OSManualOTA]"
# 4. Look for "Background Fetch triggered" messages
```

---

## Important Limitations

### iOS Controls Timing

⚠️ **You cannot control when iOS wakes your app**

- Minimum interval: **~15 minutes** (BGTaskScheduler)
- Actual interval: Determined by iOS based on usage patterns
- Apps used frequently: Get more background time
- Apps rarely used: Get less background time

### Battery Considerations

iOS may reduce or disable background fetching when:
- Device is in Low Power Mode
- Battery level is low
- App is consuming too many resources

### Network Requirements

- Background downloads require active network connection
- iOS may defer downloads on cellular networks
- Works best on WiFi

---

## User Notifications

### Notification After Background Download

When an update is downloaded in background, the plugin can show a notification:

```swift
// Automatically shown by OSBackgroundUpdateManager
"App Update Available"
"A new version has been downloaded and will be applied when you restart the app."
```

### Notification Permissions

Request notification permissions in your app:

```javascript
// Request notification permission
cordova.plugins.notification.local.requestPermission(function(granted) {
    console.log('Notification permission:', granted);
});
```

---

## Console Logs

Look for these log messages:

### Background Fetch Triggered
```
🔄 Background Fetch triggered - checking for OTA updates...
🔄 BGAppRefreshTask triggered - checking for OTA updates...
```

### Update Check
```
🔍 Checking for updates...
✅ Server has version: 'ABC123...'
📱 Currently running: 'XYZ789...'
```

### Update Available
```
✅ Update available: ABC123...
⬇️ Progress: 15/70 files downloaded, 55 skipped
✅ Background update download completed
✅ Update downloaded in background - ready for next launch
```

### No Update
```
ℹ️ No update available
```

### Scheduled Next Fetch
```
✅ Scheduled next BGAppRefreshTask
```

---

## Production Recommendations

### 1. Enable for All Users (Default)

```javascript
// On app startup
document.addEventListener('deviceready', function() {
    OSManualOTA.enableBackgroundUpdates(true,
        function() { console.log('Background OTA enabled'); },
        function(err) { console.error('Failed to enable:', err); }
    );
});
```

### 2. Let Users Control (Optional)

```javascript
// Add toggle in app settings
function toggleBackgroundUpdates(enabled) {
    OSManualOTA.enableBackgroundUpdates(enabled,
        function() {
            localStorage.setItem('background_ota_enabled', enabled);
            alert(enabled ? 'Background updates enabled' : 'Background updates disabled');
        },
        function(err) {
            alert('Failed to change setting: ' + err);
        }
    );
}
```

### 3. Monitor Success Rate

Track how often background updates succeed:

```javascript
// In your analytics
OSManualOTA.getVersionInfo(function(info) {
    analytics.track('background_ota_status', {
        current_version: info.currentVersion,
        last_check: info.lastCheckDate,
        background_enabled: true
    });
});
```

---

## Troubleshooting

### Background Fetch Not Triggering

**Check**:
1. Background Modes enabled in plugin.xml? ✅ (automatic)
2. BGTaskScheduler identifier registered? ✅ (automatic)
3. Called `enableBackgroundUpdates(true)`? ⚠️ (required in app code)
4. App used recently? (iOS prioritizes frequently used apps)
5. Device in Low Power Mode? (disables background fetch)

**Test in Xcode**:
```bash
# Force background fetch
Debug → Simulate Background Fetch
```

### Background Downloads Failing

**Check console for**:
- Network errors (offline, server unreachable)
- Permission errors (cache directory access)
- Timeout errors (iOS gives limited background time)

**Common causes**:
- No network connection when iOS woke app
- Large update exceeding background time limit (~30 seconds)
- Disk space full

### Updates Not Showing After Background Download

**Verify**:
1. Check logs for "switchToVersion called successfully" ✅
2. Restart app (background updates need app restart)
3. Check with WiFi ON (manifest needs to be fetched)

---

## Architecture

### Components

```
┌─────────────────────────────────────┐
│   OSManualOTAPlugin.swift           │
│   - JavaScript bridge               │
│   - User-initiated downloads        │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│   OSManualOTAManager.swift          │
│   - Core OTA logic                  │
│   - checkForUpdates()               │
│   - downloadUpdate()                │
│   - swapCacheToVersion()            │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│   OSBackgroundUpdateManager.swift   │
│   - Background fetch handler        │
│   - BGTaskScheduler handler         │
│   - Silent push handler             │
└─────────────┬───────────────────────┘
              │
┌─────────────▼───────────────────────┐
│   OSAppDelegateSwizzler.m           │
│   - Auto-hooks AppDelegate methods  │
│   - No manual code changes needed   │
└─────────────────────────────────────┘
```

### No AppDelegate Changes Required

The plugin automatically swizzles AppDelegate methods, so you **don't need to modify AppDelegate**:

- ✅ `performFetchWithCompletionHandler` - Auto-hooked
- ✅ `didReceiveRemoteNotification` - Auto-hooked
- ✅ No manual code needed

---

## Next Steps

1. **Enable in your app**:
   ```javascript
   OSManualOTA.enableBackgroundUpdates(true, success, error);
   ```

2. **Test with Xcode**: Debug → Simulate Background Fetch

3. **Monitor logs**: Look for "Background Fetch triggered"

4. **Test on device**: Use app for a few days, check Console.app

5. **Deploy**: Background updates work automatically in production ✅

---

## Support

For issues or questions:
- Check console logs with `[OSManualOTA]` filter
- Verify plugin.xml has UIBackgroundModes
- Test with Xcode background fetch simulator
- Check device is not in Low Power Mode
