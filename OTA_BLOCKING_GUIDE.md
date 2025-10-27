# OTA Blocking Guide

## How Automatic OTA Blocking Works

The plugin automatically patches OutSystems' `OutSystemsManifestLoader.js` to intercept and block automatic OTA updates when enabled.

---

## The Patching Mechanism

### 1. **Automatic Patching via Hook**

When you run `cordova prepare` or `cordova build`, the plugin automatically:

1. Locates `platforms/ios/www/scripts/OutSystemsManifestLoader.js`
2. Checks if it's already patched (looks for `OSManualOTA_BlockingHook` marker)
3. If not patched, prepends blocking code to the file
4. The patched file intercepts OutSystems OTA calls

**Hook File:** `hooks/after_prepare_patch_ota.js`

### 2. **What Gets Patched**

The hook injects JavaScript code that:

- Wraps the original `OSManifestLoader.getLatestVersion()`
- Wraps the original `OSManifestLoader.getLatestManifest()`
- Checks `localStorage` for blocking state before each call
- Returns fake data if blocking is enabled
- Allows normal flow if blocking is disabled

### 3. **Blocking Check Flow**

```
App starts → OutSystems tries to check for updates
    ↓
Calls getLatestVersion()
    ↓
Patched wrapper checks: isBlockingEnabled()?
    ↓
YES → Return fake version (current) → No update triggered
NO  → Call original function → Normal OTA proceeds
```

---

## How to Enable/Disable Blocking

### Enable Blocking (Recommended)

```javascript
document.addEventListener('deviceready', function() {
    // Enable OTA blocking
    OSManualOTA.setOTABlockingEnabled(true,
        function() {
            console.log('✅ Automatic OTA updates blocked');
        },
        function(error) {
            console.error('❌ Failed to enable blocking:', error);
        }
    );
}, false);
```

**What happens:**
1. Plugin sets flag in native code (UserDefaults)
2. Plugin sets flag in localStorage (`os_manual_ota_blocking_enabled = "true"`)
3. JavaScript hook reads localStorage on next OTA check
4. Automatic updates are blocked

### Disable Blocking

```javascript
OSManualOTA.setOTABlockingEnabled(false,
    function() {
        console.log('⚠️ Automatic OTA updates re-enabled');
    },
    function(error) {
        console.error('❌ Failed to disable blocking:', error);
    }
);
```

**What happens:**
1. Plugin clears flag in native code
2. Plugin clears flag in localStorage (`os_manual_ota_blocking_enabled = "false"`)
3. JavaScript hook allows normal OTA flow
4. Automatic updates work as before

### Check Blocking Status

```javascript
OSManualOTA.isOTABlockingEnabled(
    function(result) {
        console.log('Blocking enabled:', result.enabled);
    },
    function(error) {
        console.error('Error:', error);
    }
);
```

---

## The Injected Code

Here's what gets added to `OutSystemsManifestLoader.js`:

```javascript
(function() {
    // Mark as patched
    window.OSManualOTA_BlockingHook = true;

    // Store reference to original OSManifestLoader
    var OriginalOSManifestLoader = window.OSManifestLoader || {};

    // Store original functions
    var originalGetLatestVersion = OriginalOSManifestLoader.getLatestVersion;
    var originalGetLatestManifest = OriginalOSManifestLoader.getLatestManifest;

    // Helper to check if blocking is enabled
    function isBlockingEnabled() {
        if (!window.OSManualOTA) {
            return false; // Plugin not loaded, allow OTA
        }

        // Check localStorage
        var blockingEnabled = localStorage.getItem('os_manual_ota_blocking_enabled');
        return blockingEnabled === 'true';
    }

    // Helper to get current version
    function getCurrentVersion() {
        return localStorage.getItem('os_manual_ota_current_version') || 'unknown';
    }

    // Override getLatestVersion
    if (originalGetLatestVersion) {
        OriginalOSManifestLoader.getLatestVersion = function() {
            if (isBlockingEnabled()) {
                console.log('[OSManualOTA] 🚫 Blocking automatic version check');
                return Promise.resolve({ versionToken: getCurrentVersion() });
            }

            console.log('[OSManualOTA] ✅ Allowing automatic version check');
            return originalGetLatestVersion.apply(this, arguments);
        };
    }

    // Override getLatestManifest
    if (originalGetLatestManifest) {
        OriginalOSManifestLoader.getLatestManifest = function() {
            if (isBlockingEnabled()) {
                console.log('[OSManualOTA] 🚫 Blocking automatic manifest fetch');
                return Promise.resolve({
                    manifest: {
                        versionToken: getCurrentVersion(),
                        urlVersions: {}
                    }
                });
            }

            console.log('[OSManualOTA] ✅ Allowing automatic manifest fetch');
            return originalGetLatestManifest.apply(this, arguments);
        };
    }

    // Update window.OSManifestLoader
    window.OSManifestLoader = OriginalOSManifestLoader;

    console.log('[OSManualOTA] ✅ Blocking hook active');
})();
```

---

## Testing the Patch

### 1. Verify Patching

After `cordova prepare`, check the patched file:

```bash
cat platforms/ios/www/scripts/OutSystemsManifestLoader.js | head -50
```

You should see:
```
// ============================================================================
// OSManualOTA Plugin - Automatic OTA Blocking Hook
// ============================================================================
```

### 2. Test Blocking in Action

**With Safari Web Inspector connected:**

1. Enable blocking:
   ```javascript
   OSManualOTA.setOTABlockingEnabled(true);
   ```

2. Restart the app (or reload webview)

3. Watch console logs:
   ```
   [OSManualOTA] Blocking hook active
   [OSManualOTA] 🚫 Blocking automatic version check
   ```

4. Disable blocking:
   ```javascript
   OSManualOTA.setOTABlockingEnabled(false);
   ```

5. Restart the app

6. Watch console logs:
   ```
   [OSManualOTA] Blocking hook active
   [OSManualOTA] ✅ Allowing automatic version check
   ```

### 3. Test Manual Updates Still Work

Even with blocking enabled, manual updates should work:

```javascript
// Blocking is enabled
OSManualOTA.setOTABlockingEnabled(true);

// But manual check still works!
OSManualOTA.checkForUpdates(function(result) {
    console.log('Manual check result:', result);
});
```

**Why?** Manual checks use native code directly, bypassing the JavaScript hook.

---

## Debugging

### Check if Patch is Active

```javascript
if (window.OSManualOTA_BlockingHook) {
    console.log('✅ Patch is active');
} else {
    console.log('❌ Patch not found - run cordova prepare');
}
```

### Check Blocking State

```javascript
var blockingEnabled = localStorage.getItem('os_manual_ota_blocking_enabled');
console.log('Blocking state:', blockingEnabled);
```

### Check Current Version

```javascript
var currentVersion = localStorage.getItem('os_manual_ota_current_version');
console.log('Current version:', currentVersion);
```

### Watch All OTA-Related Logs

In Safari Web Inspector, filter console by:
```
[OSManualOTA]
```

You'll see:
- ✅ Blocking hook active
- 🚫 Blocking automatic version check
- ✅ Allowing automatic version check
- Blocking state updated: enabled/disabled

---

## Advanced Configuration

### Change Blocking at Runtime

You can toggle blocking dynamically:

```javascript
// Disable OTA during critical operations
function startCriticalOperation() {
    OSManualOTA.setOTABlockingEnabled(true);
    // ... do critical work ...
}

// Re-enable OTA when safe
function finishCriticalOperation() {
    OSManualOTA.setOTABlockingEnabled(false);
}
```

### Block OTA on First Launch

```javascript
document.addEventListener('deviceready', function() {
    // Check if first launch
    var hasLaunched = localStorage.getItem('app_has_launched');

    if (!hasLaunched) {
        // First launch - enable blocking
        OSManualOTA.setOTABlockingEnabled(true);
        localStorage.setItem('app_has_launched', 'true');
        console.log('First launch - OTA blocking enabled');
    }
}, false);
```

### Conditional Blocking

```javascript
// Only block OTA in production
if (window.location.hostname !== 'localhost') {
    OSManualOTA.setOTABlockingEnabled(true);
}

// Or based on user preference
if (userPreferences.manualUpdatesOnly) {
    OSManualOTA.setOTABlockingEnabled(true);
}
```

---

## Troubleshooting

### Issue: Patch Not Working

**Symptoms:** Automatic OTA still happens despite blocking enabled

**Solutions:**
1. Check if patched:
   ```bash
   grep "OSManualOTA_BlockingHook" platforms/ios/www/scripts/OutSystemsManifestLoader.js
   ```

2. Re-run prepare:
   ```bash
   cordova prepare ios
   ```

3. Check localStorage:
   ```javascript
   console.log(localStorage.getItem('os_manual_ota_blocking_enabled'));
   ```

4. Verify plugin is loaded:
   ```javascript
   console.log(window.OSManualOTA); // Should not be undefined
   ```

### Issue: Hook Runs Before Plugin Loaded

**Symptoms:** Console shows "Plugin not loaded yet, allowing OTA"

**Solution:** This is normal on first launch. The hook allows OTA until plugin is ready. On subsequent app opens, localStorage will be set and blocking will work.

### Issue: Patch Gets Overwritten

**Symptoms:** Patch disappears after build

**Cause:** The `www` folder gets regenerated from source

**Solution:** Hook runs automatically after prepare - patch is reapplied. No action needed.

### Issue: Can't Disable Blocking

**Symptoms:** Even with `setOTABlockingEnabled(false)`, OTA is still blocked

**Solution:** Clear localStorage manually:
```javascript
localStorage.removeItem('os_manual_ota_blocking_enabled');
```

---

## How It Compares to Your Original Approach

### Your Original Manual Patch

You mentioned manually editing `OutSystemsManifestLoader.js`:

```javascript
getLatestVersion() → replaced with fake Promise.resolve(...)
getLatestManifest() → replaced with fake module manifest
```

**Pros:**
- Direct and simple
- Works immediately

**Cons:**
- Manual process (error-prone)
- Gets overwritten on rebuild
- Can't be toggled dynamically
- No way to re-enable automatic OTA

### Plugin's Automatic Patch

**Pros:**
- ✅ Automatic (via hook)
- ✅ Survives rebuilds (reapplied automatically)
- ✅ Can be toggled dynamically (enable/disable anytime)
- ✅ Controlled via JavaScript API
- ✅ Synced between native and JavaScript
- ✅ Logs actions for debugging

**Cons:**
- Slightly more complex (but handled automatically)

---

## Production Checklist

Before deploying to production:

- [ ] Test blocking enabled - verify automatic OTA doesn't run
- [ ] Test blocking disabled - verify automatic OTA works
- [ ] Test manual updates work when blocking enabled
- [ ] Test toggling blocking on/off at runtime
- [ ] Verify patch survives `cordova prepare`
- [ ] Check console logs for hook activity
- [ ] Test on multiple app launches
- [ ] Test with different network conditions

---

## Summary

The plugin provides **automatic, dynamic OTA blocking** with:

1. **Automatic patching** via Cordova hook (no manual editing)
2. **Dynamic control** via JavaScript API
3. **Persistent state** via localStorage
4. **Full logging** for debugging
5. **Manual updates** still work regardless of blocking state

Enable blocking once, and automatic OTA updates are blocked forever (until you disable it).

**Recommended setup:**

```javascript
document.addEventListener('deviceready', function() {
    // Enable blocking on app launch
    OSManualOTA.setOTABlockingEnabled(true);

    // Enable background updates
    OSManualOTA.enableBackgroundUpdates(true);

    // Now updates only happen:
    // - Via background fetch (silent)
    // - Via silent push (triggered)
    // - Via manual user action
    // But NOT on app startup!
}, false);
```

🎉 **Automatic startup OTA is now blocked!**
