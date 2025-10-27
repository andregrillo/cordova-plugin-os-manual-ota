# Android Implementation TODO

This branch is dedicated to implementing Android support for the Manual OTA plugin.

---

## Current Status

- ✅ **iOS Implementation** - Complete and merged to `main`
- 🚧 **Android Implementation** - In progress on this branch

---

## What Needs to Be Implemented

### 1. **Android Native Code** (Java/Kotlin)

Create Android equivalents of iOS components:

#### **Core Classes:**
- [ ] `OSManualOTAManager.java/kt` - Main OTA manager (equivalent to iOS Swift version)
- [ ] `OSManualOTAPlugin.java/kt` - Cordova plugin bridge
- [ ] `OSBackgroundUpdateManager.java/kt` - Background updates handler
- [ ] `OSUpdateModels.java/kt` - Data models and errors

#### **Background Operations:**
- [ ] WorkManager integration (Android's equivalent to Background Fetch)
- [ ] Firebase Cloud Messaging (FCM) for silent push notifications
- [ ] AlarmManager fallback for older devices

#### **AppDelegate Equivalent:**
- [ ] Application class extension or MainActivity hooks
- [ ] Broadcast receiver for FCM messages
- [ ] No swizzling needed (Android uses different pattern)

### 2. **Android-Specific Features**

#### **Download Manager:**
- [ ] Use Android DownloadManager or OkHttp
- [ ] Handle network type detection (WiFi/Cellular)
- [ ] Battery optimization considerations
- [ ] Doze mode handling

#### **Storage:**
- [ ] SharedPreferences for blocking state
- [ ] File system for downloaded assets
- [ ] Cache management

#### **Permissions:**
- [ ] Internet permission (manifest)
- [ ] Background execution permission (manifest)
- [ ] Battery optimization exclusion (optional)

### 3. **OutSystems Integration**

#### **Android Cache System:**
- [ ] Research OutSystems Android cache structure
- [ ] Equivalent of `OSCacheResources` for Android
- [ ] Asset hash comparison
- [ ] Incremental update logic

#### **Manifest Loader Patching:**
- [ ] Hook into OutSystems WebView
- [ ] Intercept JavaScript calls
- [ ] Or use a different approach (investigate)

### 4. **Plugin Configuration**

Update `plugin.xml`:
- [ ] Add Android platform section
- [ ] Configure permissions
- [ ] Register services and receivers
- [ ] Add Gradle dependencies

### 5. **Documentation**

- [ ] Update README.md with Android setup
- [ ] Create ANDROID_INTEGRATION_GUIDE.md
- [ ] Document Android-specific features
- [ ] Add troubleshooting for Android

---

## Architecture (Proposed)

### **Android Components Structure:**

```
src/android/
├── OSManualOTAPlugin.kt               # Cordova plugin bridge
├── OSManualOTAManager.kt              # Main OTA logic
├── OSBackgroundUpdateManager.kt       # Background operations
├── OSUpdateModels.kt                  # Data classes
├── workers/
│   └── OTAUpdateWorker.kt            # WorkManager worker
├── receivers/
│   └── FCMReceiver.kt                # FCM message receiver
└── services/
    └── OTAUpdateService.kt           # Foreground service (optional)
```

### **Background Updates Flow:**

```
WorkManager (periodic) or FCM (triggered)
    ↓
OTAUpdateWorker
    ↓
OSManualOTAManager.checkForUpdates()
    ↓
OSManualOTAManager.downloadUpdate()
    ↓
OutSystems Android Cache
    ↓
Apply on next app launch
```

---

## Key Differences: iOS vs Android

| Feature | iOS | Android |
|---------|-----|---------|
| **Background Tasks** | Background Fetch, BGTaskScheduler | WorkManager, JobScheduler |
| **Push Notifications** | APNS (Silent Push) | FCM (Data Messages) |
| **Method Swizzling** | Yes (Objective-C runtime) | No (use different pattern) |
| **Storage** | UserDefaults | SharedPreferences |
| **WebView** | WKWebView | Android WebView |
| **Permissions** | Minimal | Internet, Background |

---

## Implementation Plan

### **Phase 1: Basic Structure** (Week 1)
1. Create Android plugin structure
2. Implement basic Cordova bridge
3. Add to plugin.xml
4. Test plugin installation

### **Phase 2: OTA Manager** (Week 2)
1. Implement check for updates
2. Implement download logic
3. Add progress tracking
4. Test manual updates

### **Phase 3: Background Updates** (Week 3)
1. Implement WorkManager worker
2. Add FCM integration
3. Test background updates
4. Handle battery optimization

### **Phase 4: Integration** (Week 4)
1. Integrate with OutSystems cache
2. Add manifest loader patching
3. Test incremental updates
4. Add rollback support

### **Phase 5: Documentation** (Week 5)
1. Write Android setup guide
2. Add troubleshooting
3. Create examples
4. Update main README

---

## Research Needed

### **OutSystems Android Cache:**
- [ ] How does OutSystems cache work on Android?
- [ ] Where are assets stored?
- [ ] How to access cache programmatically?
- [ ] Hash verification mechanism?

### **WebView Hooking:**
- [ ] How to intercept OutSystems OTA on Android?
- [ ] WebView JavaScript injection?
- [ ] Or use native interception?

### **Background Restrictions:**
- [ ] Android 12+ background restrictions
- [ ] Doze mode impact
- [ ] Battery optimization handling
- [ ] Best practices for reliable background updates

---

## Testing Strategy

### **Unit Tests:**
- [ ] Test version checking
- [ ] Test hash comparison
- [ ] Test download logic
- [ ] Test rollback

### **Integration Tests:**
- [ ] Test with OutSystems app
- [ ] Test on multiple Android versions (8+)
- [ ] Test on different devices
- [ ] Test background updates

### **Manual Tests:**
- [ ] Install plugin
- [ ] Enable blocking
- [ ] Trigger manual update
- [ ] Test background fetch
- [ ] Test FCM push
- [ ] Test rollback
- [ ] Test crash recovery

---

## Resources

### **Android Documentation:**
- [WorkManager](https://developer.android.com/topic/libraries/architecture/workmanager)
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [Background Tasks](https://developer.android.com/guide/background)
- [Cordova Android](https://cordova.apache.org/docs/en/latest/guide/platforms/android/)

### **Similar Implementations:**
- Cordova plugin background fetch (for reference)
- Cordova plugin FCM (for push notifications)
- OutSystems Android documentation

---

## Questions to Answer

1. How does OutSystems handle OTA on Android?
2. What's the Android equivalent of `OutSystemsManifestLoader.js`?
3. How to access OutSystems cache on Android?
4. Best way to hook into app lifecycle on Android?
5. WorkManager vs JobScheduler vs AlarmManager - which to use?
6. How to ensure background updates work on all Android versions?

---

## Notes

- **Start with manual updates first** (simpler)
- **Then add background updates** (more complex)
- **Test thoroughly on real devices** (emulator might not show real behavior)
- **Consider Android version fragmentation** (support Android 8+)
- **Battery optimization is critical** (users often disable it)

---

## Success Criteria

Android implementation is complete when:

- [x] Manual OTA updates work
- [x] Background updates work via WorkManager
- [x] FCM silent push works
- [x] Automatic blocking works
- [x] Rollback works
- [x] Integration with OutSystems cache works
- [x] Documentation is complete
- [x] Tests pass on Android 8, 10, 12, 13+

---

## Current Branch: `feature/android-implementation`

**How to work on this branch:**

```bash
# Make sure you're on the Android branch
git checkout feature/android-implementation

# Create your Android implementation
# ... code ...

# Commit your changes
git add .
git commit -m "Android: Implement ..."

# When complete, merge to main
git checkout main
git merge feature/android-implementation
```

---

**Let's build Android support! 🤖**
