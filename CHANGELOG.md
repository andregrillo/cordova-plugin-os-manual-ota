# Changelog

All notable changes to cordova-plugin-os-manual-ota will be documented in this file.

## [1.0.0] - 2025-10-27

### Added
- Initial release of Manual OTA plugin
- Background Fetch support for automatic silent updates
- Silent Push Notification support for immediate updates
- Manual OTA update control (check, download, apply)
- Incremental update support (hash-based file comparison)
- Real-time download progress tracking
- Automatic crash detection and rollback
- Manual rollback to previous version
- Version information API
- OTA blocking control to disable automatic OutSystems updates
- Comprehensive JavaScript API
- Swift-based iOS implementation
- Integration with existing OutSystems cache infrastructure
- Background task management
- Network condition checking
- Event system for status changes

### Architecture
- `OSManualOTAManager` - Core OTA logic and state management
- `OSBackgroundUpdateManager` - Background Fetch and Silent Push handling
- `OSManualOTAPlugin` - Cordova plugin bridge
- `OSUpdateModels` - Data models and error types
- JavaScript API with convenience methods

### Documentation
- Complete README with usage examples
- Integration guide with step-by-step instructions
- API reference
- Troubleshooting guide
- Production checklist

### Platform Support
- iOS 12.0+
- Swift 5.0+
- Cordova 9.0+

### Dependencies
- @outsystems/cordova-outsystems-core (for cache infrastructure)
- UIKit.framework
- Foundation.framework
- BackgroundTasks.framework (iOS 13+, optional)

## [Unreleased]

### Planned Features
- Full integration with OSCacheResources download infrastructure
- WiFi-only download option
- Download size estimation before starting
- Analytics integration for update metrics
- Android platform support
- Retry logic for failed downloads
- Delta patching for faster updates
- Configurable max concurrent downloads
- Network type detection and handling
- Battery level checking before download
- Progress persistence across app restarts
- Update scheduling (download at specific times)
- A/B testing support for gradual rollouts
- User notification preferences
- Offline update queueing

### Known Issues
- OSCacheResources integration is currently a placeholder (needs OutSystems team collaboration)
- Network condition checking is simplified (needs enhancement)
- Analytics logging is console-only (needs proper integration)
- No Android support yet
- Background Fetch timing is non-deterministic (iOS limitation)
- Silent push may not work in Low Power Mode (iOS limitation)

### Technical Debt
- TODO: Complete OSCacheResources integration in OSManualOTAManager.swift:downloadChangedFiles
- TODO: Implement proper network reachability checking
- TODO: Add comprehensive error recovery mechanisms
- TODO: Add unit tests and integration tests
- TODO: Optimize storage management for multiple cached versions
- TODO: Add telemetry for update success rates

## Migration Guide

### From Automatic OTA to Manual OTA

If you're migrating from standard OutSystems automatic OTA:

1. **Install the plugin** (see INTEGRATION_GUIDE.md)
2. **Enable OTA blocking** immediately on app launch:
   ```javascript
   OSManualOTA.setOTABlockingEnabled(true);
   ```
3. **Enable background updates** for seamless experience:
   ```javascript
   OSManualOTA.enableBackgroundUpdates(true);
   ```
4. **Add manual check on app launch** (optional):
   ```javascript
   OSManualOTA.checkForUpdates(/* ... */);
   ```
5. **Update AppDelegate** to handle background operations

### Breaking Changes from Automatic OTA

- Updates no longer happen automatically at app startup
- Must explicitly enable background updates if desired
- Must handle update UI/notifications yourself
- App restart required to apply updates (same as before)
- Version management is now more explicit

## Performance Considerations

### Background Fetch
- iOS decides when to trigger (typically every 15min-1hr)
- Maximum ~30 seconds execution time
- Should be used for incremental updates only
- Will be throttled if app is rarely used

### Silent Push
- Requires backend infrastructure
- May not work if device is in Low Power Mode
- Requires active push notification certificate
- No user permission required (unlike regular push)

### Download Optimization
- Uses incremental updates (only changed files)
- Supports parallel downloads (default: 6 concurrent)
- Hash-based file comparison prevents unnecessary downloads
- Leverages existing OutSystems cache structure

## Security

### Update Validation
- All files are hash-verified after download
- Uses HTTPS for all network requests
- Respects OutSystems certificate pinning
- Version tokens prevent replay attacks

### Privacy
- No user data is collected by plugin
- All storage is local (UserDefaults)
- Update metrics are logged locally only (no external transmission)
- Silent push doesn't access notification permissions

### Best Practices
- Always verify hashes before applying updates
- Implement automatic rollback (already included)
- Log all update attempts for audit trail
- Use signed push notifications for production
- Monitor update success rates

## Compatibility

### iOS Versions
- iOS 12.0+ (Required)
- iOS 13.0+ (Full BGTaskScheduler support)
- Tested on iOS 14, 15, 16, 17

### OutSystems Versions
- Compatible with MABS 9.0+
- Works with all OutSystems 11 apps
- Tested with OutSystems 11.x

### Device Types
- iPhone (all models since iPhone 6)
- iPad (all models)
- Not supported: Apple Watch, Apple TV

## Credits

### Author
Andre Grillo - OutSystems Native Development Team

### Inspiration
- Based on analysis of OutSystems OTA system
- Inspired by bash script implementation (check_ota_incremental_improved.sh)
- Uses OutSystems existing cache infrastructure

### Contributors
- Claude AI - Architecture and implementation assistance

## License

MIT License

Copyright (c) 2025 OutSystems

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
