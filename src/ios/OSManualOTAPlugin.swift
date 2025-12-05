//
//  OSManualOTAPlugin.swift
//  OutSystems Manual OTA Plugin
//
//  Cordova plugin bridge for JavaScript to native communication
//

import Foundation

@objc(OSManualOTAPlugin)
class OSManualOTAPlugin: CDVPlugin {

    // MARK: - Properties
    private let otaManager = OSManualOTAManager.shared
    private var backgroundManager: OSBackgroundUpdateManager {
        return OSBackgroundUpdateManager.shared
    }

    // Store callback IDs for progress updates
    private var downloadCallbackId: String?

    // MARK: - Plugin Lifecycle
    override func pluginInitialize() {
        super.pluginInitialize()
        print("🚀 OSManualOTA Plugin initialized")

        // Configure OTA manager with app settings
        configureFromSettings()

        // Try to read current version from localStorage (set by JavaScript hook)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.readVersionFromLocalStorage()
            // Also sync with actual running version from OutSystems cache
            self?.syncRunningVersion()
        }

        // ALSO: Try to read version directly from OutSystems JavaScript after a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.readVersionFromOutSystemsJS()
        }

        // Listen for OTA blocking status changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(otaBlockingStatusChanged(_:)),
            name: .otaBlockingStatusChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration
    @objc(configure:)
    func configure(_ command: CDVInvokedUrlCommand) {
        guard let config = command.argument(at: 0) as? [String: Any],
              let baseURL = config["baseURL"] as? String,
              let hostname = config["hostname"] as? String,
              let applicationPath = config["applicationPath"] as? String else {
            let result = CDVPluginResult(status: .error, messageAs: "Invalid configuration parameters")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        // Get optional current version from JavaScript
        let currentVersion = config["currentVersion"] as? String

        otaManager.configure(
            baseURL: baseURL,
            hostname: hostname,
            applicationPath: applicationPath,
            currentVersion: currentVersion
        )

        let result = CDVPluginResult(status: .ok, messageAs: "Configuration saved")
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Auto-sync Version from JavaScript
    @objc(syncVersionFromJS:)
    func syncVersionFromJS(_ command: CDVInvokedUrlCommand) {
        guard let version = command.argument(at: 0) as? String, !version.isEmpty else {
            let result = CDVPluginResult(status: .error, messageAs: "Invalid version")
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        print("[OSManualOTA] 📱 Received version from JavaScript: '\(version)'")
        let storedVersion = otaManager.getCurrentVersion()

        if version != storedVersion {
            print("[OSManualOTA] 🔄 Updating stored version from '\(storedVersion)' to '\(version)'")
            otaManager.saveCurrentVersion(version)
            print("[OSManualOTA] ✅ Version synced successfully")
        } else {
            print("[OSManualOTA] ✅ Version already correct - no update needed")
        }

        let result = CDVPluginResult(status: .ok, messageAs: "Version synced")
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Check for Updates
    @objc(checkForUpdates:)
    func checkForUpdates(_ command: CDVInvokedUrlCommand) {
        // First, log JavaScript versions for comprehensive debugging
        logJavaScriptVersions {
            // Then proceed with normal update check
            self.commandDelegate.run {
                self.otaManager.checkForUpdates { hasUpdate, version, error in
                    if let error = error {
                        let result = CDVPluginResult(
                            status: .error,
                            messageAs: error.localizedDescription
                        )
                        self.commandDelegate.send(result, callbackId: command.callbackId)
                    } else {
                        let response: [String: Any] = [
                            "hasUpdate": hasUpdate,
                            "version": version ?? ""
                        ]
                        let result = CDVPluginResult(status: .ok, messageAs: response)
                        self.commandDelegate.send(result, callbackId: command.callbackId)
                    }
                }
            }
        }
    }

    // MARK: - Download Update
    @objc(downloadUpdate:)
    func downloadUpdate(_ command: CDVInvokedUrlCommand) {
        // Store callback ID for progress updates
        downloadCallbackId = command.callbackId

        commandDelegate.run {
            self.otaManager.downloadUpdate(
                progressHandler: { [weak self] downloaded, total, skipped in
                    self?.sendProgressUpdate(downloaded: downloaded, total: total, skipped: skipped)
                },
                errorHandler: { [weak self] error in
                    self?.sendError(message: error)
                },
                completion: { [weak self] success in
                    guard let self = self else { return }

                    // Note: We don't reload the webview here because:
                    // 1. The manifest has been persisted to disk
                    // 2. The new version will load automatically on next app start
                    // 3. Webview reload can cause crashes and isn't necessary
                    if success {
                        print("[OSManualOTA] ✅ Update ready! Close and reopen the app to load new version.")
                    }

                    let response: [String: Any] = [
                        "success": success
                    ]

                    let result = CDVPluginResult(
                        status: success ? .ok : .error,
                        messageAs: response
                    )

                    // Final message
                    result?.setKeepCallbackAs(false)
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                    self.downloadCallbackId = nil
                }
            )
        }
    }

    // MARK: - Apply Update
    @objc(applyUpdate:)
    func applyUpdate(_ command: CDVInvokedUrlCommand) {
        commandDelegate.run {
            self.otaManager.applyUpdate { success, error in
                if let error = error {
                    let result = CDVPluginResult(
                        status: .error,
                        messageAs: error.localizedDescription
                    )
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                } else {
                    let response: [String: Any] = [
                        "success": success,
                        "message": "Update will be applied on next app restart"
                    ]
                    let result = CDVPluginResult(status: .ok, messageAs: response)
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
            }
        }
    }

    // MARK: - Rollback
    @objc(rollback:)
    func rollback(_ command: CDVInvokedUrlCommand) {
        commandDelegate.run {
            self.otaManager.rollbackToPreviousVersion { success, error in
                if let error = error {
                    let result = CDVPluginResult(
                        status: .error,
                        messageAs: error.localizedDescription
                    )
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                } else {
                    let response: [String: Any] = [
                        "success": success,
                        "message": "Rollback completed"
                    ]
                    let result = CDVPluginResult(status: .ok, messageAs: response)
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
            }
        }
    }

    // MARK: - Cancel Download
    @objc(cancelDownload:)
    func cancelDownload(_ command: CDVInvokedUrlCommand) {
        otaManager.cancelDownload()

        let result = CDVPluginResult(
            status: .ok,
            messageAs: "Download cancelled"
        )
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Version Info
    @objc(getVersionInfo:)
    func getVersionInfo(_ command: CDVInvokedUrlCommand) {
        otaManager.getCurrentVersionInfo { info in
            let result = CDVPluginResult(status: .ok, messageAs: info)
            self.commandDelegate.send(result, callbackId: command.callbackId)
        }
    }

    // MARK: - OTA Blocking Control
    @objc(setOTABlockingEnabled:)
    func setOTABlockingEnabled(_ command: CDVInvokedUrlCommand) {
        guard let enabled = command.argument(at: 0) as? Bool else {
            let result = CDVPluginResult(
                status: .error,
                messageAs: "Invalid parameter: expected boolean"
            )
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        otaManager.setOTABlockingEnabled(enabled)

        // Sync to JavaScript localStorage
        let js = """
        localStorage.setItem('os_manual_ota_blocking_enabled', '\(enabled ? "true" : "false")');
        localStorage.setItem('os_manual_ota_current_version', '\(otaManager.isOTABlockingEnabled())');
        console.log('[OSManualOTA] Blocking state synced to localStorage: \(enabled)');
        """
        commandDelegate.evalJs(js)

        let response: [String: Any] = [
            "enabled": enabled,
            "message": enabled ? "OTA blocking enabled" : "OTA blocking disabled"
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(isOTABlockingEnabled:)
    func isOTABlockingEnabled(_ command: CDVInvokedUrlCommand) {
        let enabled = otaManager.isOTABlockingEnabled()

        let response: [String: Any] = [
            "enabled": enabled
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Splash Screen Bypass Control
    @objc(setSplashBypassEnabled:)
    func setSplashBypassEnabled(_ command: CDVInvokedUrlCommand) {
        guard let enabled = command.argument(at: 0) as? Bool else {
            let result = CDVPluginResult(
                status: .error,
                messageAs: "Invalid parameter: expected boolean"
            )
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        // Set splash bypass state
        otaManager.setSplashBypassEnabled(enabled)

        // Also sync to localStorage for JavaScript hook
        let jsCode = """
        localStorage.setItem('os_manual_ota_splash_bypass_enabled', '\(enabled)');
        console.log('[OSManualOTA] Splash bypass state synced to localStorage: \(enabled)');
        """
        commandDelegate.evalJs(jsCode)

        let response: [String: Any] = [
            "enabled": enabled,
            "message": enabled ? "Splash bypass enabled" : "Splash bypass disabled"
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(isSplashBypassEnabled:)
    func isSplashBypassEnabled(_ command: CDVInvokedUrlCommand) {
        let enabled = otaManager.isSplashBypassEnabled()

        let response: [String: Any] = [
            "enabled": enabled
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Background Updates Control
    @objc(enableBackgroundUpdates:)
    func enableBackgroundUpdates(_ command: CDVInvokedUrlCommand) {
        guard let enabled = command.argument(at: 0) as? Bool else {
            let result = CDVPluginResult(
                status: .error,
                messageAs: "Invalid parameter: expected boolean"
            )
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        backgroundManager.enableBackgroundUpdates(enabled)

        let response: [String: Any] = [
            "enabled": enabled,
            "message": enabled ? "Background updates enabled" : "Background updates disabled"
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(setBackgroundFetchInterval:)
    func setBackgroundFetchInterval(_ command: CDVInvokedUrlCommand) {
        guard let interval = command.argument(at: 0) as? Double else {
            let result = CDVPluginResult(
                status: .error,
                messageAs: "Invalid parameter: expected number"
            )
            commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        backgroundManager.setMinimumBackgroundFetchInterval(interval)

        let response: [String: Any] = [
            "interval": interval,
            "message": "Background fetch interval set to \(interval) seconds"
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Debug Methods

    @objc(resetOTAState:)
    func resetOTAState(_ command: CDVInvokedUrlCommand) {
        otaManager.resetOTAState()

        let response: [String: Any] = [
            "message": "OTA state reset - all cached versions and hashes cleared"
        ]

        let result = CDVPluginResult(status: .ok, messageAs: response)
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Private Helpers
    private func configureFromSettings() {
        // Try to get configuration from Cordova settings or app config
        if let settings = commandDelegate.settings as? [String: Any] {
            if let baseURL = settings["OSManualOTABaseURL"] as? String,
               let hostname = settings["OSManualOTAHostname"] as? String,
               let appPath = settings["OSManualOTAApplicationPath"] as? String {
                otaManager.configure(baseURL: baseURL, hostname: hostname, applicationPath: appPath)
                print("✅ Configured OTA from settings")
            }
        }
    }

    private func sendProgressUpdate(downloaded: Int, total: Int, skipped: Int) {
        guard let callbackId = downloadCallbackId else { return }

        let progress: [String: Any] = [
            "downloaded": downloaded,
            "total": total,
            "skipped": skipped,
            "percentage": total > 0 ? Double(downloaded) / Double(total) * 100 : 0
        ]

        let result = CDVPluginResult(status: .ok, messageAs: progress)
        result?.setKeepCallbackAs(true) // Keep callback for multiple progress updates
        commandDelegate.send(result, callbackId: callbackId)
    }

    private func sendError(message: String) {
        guard let callbackId = downloadCallbackId else { return }

        let result = CDVPluginResult(status: .error, messageAs: message)
        result?.setKeepCallbackAs(true) // Keep callback active
        commandDelegate.send(result, callbackId: callbackId)
    }

    @objc private func otaBlockingStatusChanged(_ notification: Notification) {
        guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }

        // Notify JavaScript side via event
        let js = "cordova.fireDocumentEvent('OSManualOTA.blockingStatusChanged', {enabled: \(enabled)});"
        commandDelegate.evalJs(js)
    }

    private func readVersionFromLocalStorage() {
        let js = "localStorage.getItem('os_manual_ota_current_version')"

        webViewEngine.evaluateJavaScript(js) { [weak self] result, error in
            if error != nil {
                print("[OSManualOTA] Error reading version from localStorage: \(String(describing: error))")
                return
            }

            if let version = result as? String, !version.isEmpty, version != "null" {
                // Validate that it looks like a version token (not a boolean or other value)
                // OutSystems version tokens are typically base64-like strings
                if version == "false" || version == "true" || version == "unknown" {
                    print("[OSManualOTA] ⚠️ Invalid version in localStorage: '\(version)' - ignoring")
                    return
                }

                print("[OSManualOTA] 📱 Read version from localStorage: \(version)")
                // Just save the version directly - configuration is already set from settings
                self?.otaManager.saveCurrentVersion(version)
            } else {
                print("[OSManualOTA] No version found in localStorage yet")
            }
        }
    }

    private func syncRunningVersion() {
        // Get the ACTUAL running version from OutSystems cache and sync it with our storage
        print("[OSManualOTA] 🔄 Syncing with actual running version...")

        if let appCache = otaManager.getOutSystemsCache(),
           let runningFrame = appCache.getCurrentRunningFrame() {
            let actualVersion = runningFrame.versionToken
            let storedVersion = otaManager.getCurrentVersion()

            print("[OSManualOTA] 📱 Actual running version: '\(actualVersion)'")
            print("[OSManualOTA] 💾 Stored version: '\(storedVersion)'")

            if actualVersion != storedVersion {
                print("[OSManualOTA] ⚠️ Version mismatch detected! Updating stored version...")
                otaManager.saveCurrentVersion(actualVersion)
                print("[OSManualOTA] ✅ Stored version updated to: '\(actualVersion)'")
            } else {
                print("[OSManualOTA] ✅ Versions match - no sync needed")
            }

            // Inject JavaScript to handle offline moduleinfo loading
            injectOfflineModuleinfoFallback(version: actualVersion)
        } else {
            print("[OSManualOTA] ⚠️ Could not get running version from OutSystems cache yet")
        }
    }

    private func injectOfflineModuleinfoFallback(version: String) {
        print("[OSManualOTA] 💉 Injecting offline moduleinfo fallback for version: \(version)")

        // Wait a bit longer to ensure webView is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, let webView = self.webViewEngine else {
                print("[OSManualOTA] ⚠️ WebView not available for JavaScript injection")
                return
            }

            // Store the current version in localStorage so JavaScript can access it
            let setVersionJS = """
            (function() {
                try {
                    if (typeof localStorage !== 'undefined') {
                        localStorage.setItem('os_manual_ota_current_version', '\(version)');
                        console.log('[OSManualOTA] ✅ Stored current version in localStorage: \(version)');
                        return true;
                    }
                    return false;
                } catch (e) {
                    console.log('[OSManualOTA] ❌ Error setting localStorage: ' + e);
                    return false;
                }
            })();
            """

            webView.evaluateJavaScript(setVersionJS) { result, error in
                if error != nil {
                    print("[OSManualOTA] ⚠️ Failed to set localStorage: \(String(describing: error))")
                } else {
                    print("[OSManualOTA] ✅ Version injected into localStorage")
                }
            }

            // Inject fallback handler that loads cached moduleinfo when offline
            // Wait a bit more for OSManifestLoader to be available
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, let webView = self.webViewEngine else {
                    print("[OSManualOTA] ⚠️ WebView not available for fallback injection")
                    return
                }

                let fallbackJS = """
                (function() {
                    try {
                        console.log('[OSManualOTA] 💉 Setting up offline moduleinfo fallback...');

                        if (typeof OSManifestLoader !== 'undefined') {
                            // Get cached version from localStorage
                            var cachedVersion = localStorage.getItem('os_manual_ota_current_version');

                            if (cachedVersion) {
                                console.log('[OSManualOTA] 🔄 Found cached version in localStorage: ' + cachedVersion);

                                // CRITICAL: Replace the prefetchedVersion that already failed
                                // This is what the app uses to determine which files to load!
                                OSManifestLoader.prefetchedVersion = OSManifestLoader.getLatestManifest(cachedVersion)
                                    .then(function(manifest) {
                                        console.log('[OSManualOTA] ✅ Loaded cached moduleinfo for version: ' + cachedVersion);
                                        // Return version info in the expected format
                                        return {
                                            versionToken: cachedVersion,
                                            manifest: manifest
                                        };
                                    })
                                    .catch(function(error) {
                                        console.log('[OSManualOTA] ❌ Failed to load cached moduleinfo: ' + error);
                                        throw error;
                                    });

                                console.log('[OSManualOTA] ✅ Replaced prefetchedVersion with cached moduleinfo');

                                // Also wrap getLatestVersion for future calls
                                var originalGetLatestVersion = OSManifestLoader.getLatestVersion;
                                OSManifestLoader.getLatestVersion = function(options) {
                                    return originalGetLatestVersion(options).catch(function(error) {
                                        console.log('[OSManualOTA] ⚠️ getLatestVersion failed, using cached version: ' + cachedVersion);
                                        return OSManifestLoader.getLatestManifest(cachedVersion).then(function(manifest) {
                                            return {
                                                versionToken: cachedVersion,
                                                manifest: manifest
                                            };
                                        });
                                    });
                                };

                                return true;
                            } else {
                                console.log('[OSManualOTA] ⚠️ No cached version in localStorage');
                                return false;
                            }
                        } else {
                            console.log('[OSManualOTA] ⚠️ OSManifestLoader not available yet');
                            return false;
                        }
                    } catch (e) {
                        console.log('[OSManualOTA] ❌ Error setting up fallback: ' + e);
                        return false;
                    }
                })();
                """

                webView.evaluateJavaScript(fallbackJS) { result, error in
                    if error != nil {
                        print("[OSManualOTA] ⚠️ Failed to inject fallback: \(String(describing: error))")
                    } else {
                        print("[OSManualOTA] ✅ Offline moduleinfo fallback injected successfully")
                    }
                }
            }
        }
    }

    private func readVersionFromOutSystemsJS() {
        print("[OSManualOTA] 🔄 Reading version from OutSystems JavaScript...")

        // IMPORTANT: Always check cache frame version FIRST
        // The cache frame is the source of truth, not indexVersionToken from old HTML
        var runningVersion: String?
        if let appCache = otaManager.getOutSystemsCache(),
           let runningFrame = appCache.getCurrentRunningFrame() {
            runningVersion = runningFrame.versionToken
        }

        let js = "typeof OSManifestLoader !== 'undefined' && OSManifestLoader.indexVersionToken ? OSManifestLoader.indexVersionToken : null"

        webViewEngine.evaluateJavaScript(js) { [weak self] result, error in
            if error != nil {
                print("[OSManualOTA] ⚠️ Error reading from JavaScript: \(String(describing: error))")
                return
            }

            if let jsVersion = result as? String, !jsVersion.isEmpty, jsVersion != "null" {
                print("[OSManualOTA] 📱 JavaScript indexVersionToken: '\(jsVersion)'")

                // If we have a running frame version, it takes precedence
                if let actualVersion = runningVersion, !actualVersion.isEmpty {
                    print("[OSManualOTA] 🏃 Cache frame version (truth): '\(actualVersion)'")

                    if jsVersion != actualVersion {
                        print("[OSManualOTA] ⚠️ Version mismatch! JS says '\(jsVersion)' but cache says '\(actualVersion)'")
                        print("[OSManualOTA] ✅ Trusting cache frame version, NOT JavaScript")
                        // Use cache version, not JS version
                        let storedVersion = self?.otaManager.getCurrentVersion() ?? "unknown"
                        if actualVersion != storedVersion {
                            self?.otaManager.saveCurrentVersion(actualVersion)
                            print("[OSManualOTA] ✅ Stored version synced to cache frame: '\(actualVersion)'")
                        }
                    } else {
                        print("[OSManualOTA] ✅ JS and cache versions match: '\(actualVersion)'")
                        // Versions match, use either one
                        let storedVersion = self?.otaManager.getCurrentVersion() ?? "unknown"
                        if actualVersion != storedVersion {
                            self?.otaManager.saveCurrentVersion(actualVersion)
                            print("[OSManualOTA] ✅ Version synced from JavaScript: '\(actualVersion)'")
                        }
                    }
                } else {
                    // No cache frame version, fall back to JS (first run scenario)
                    print("[OSManualOTA] 📝 No cache frame version yet, using JS version: '\(jsVersion)'")
                    let storedVersion = self?.otaManager.getCurrentVersion() ?? "unknown"
                    if jsVersion != storedVersion {
                        self?.otaManager.saveCurrentVersion(jsVersion)
                        print("[OSManualOTA] ✅ Version synced from JavaScript!")
                    }
                }
            } else {
                print("[OSManualOTA] ⚠️ OSManifestLoader.indexVersionToken not available yet")
            }
        }
    }

    // Log all JavaScript version sources for comprehensive debugging
    private func logJavaScriptVersions(completion: @escaping () -> Void) {
        print("[OSManualOTA] 🌐 Checking JavaScript version sources...")

        // JavaScript code to extract all version-related values
        let js = """
        (function() {
            var result = {};

            // Check OSManifestLoader.indexVersionToken
            if (typeof OSManifestLoader !== 'undefined') {
                result.indexVersionToken = OSManifestLoader.indexVersionToken || 'undefined';
            } else {
                result.indexVersionToken = 'OSManifestLoader not loaded';
            }

            // Check localStorage
            if (typeof localStorage !== 'undefined') {
                result.localStorage = localStorage.getItem('os_manual_ota_current_version') || 'not set';
            } else {
                result.localStorage = 'localStorage not available';
            }

            return JSON.stringify(result);
        })();
        """

        webViewEngine.evaluateJavaScript(js) { result, error in
            if error != nil {
                print("[OSManualOTA] ⚠️ Error reading JavaScript versions: \(String(describing: error))")
                completion()
                return
            }

            if let jsonString = result as? String,
               let jsonData = jsonString.data(using: .utf8),
               let versions = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                print("[OSManualOTA] 📱 JavaScript Versions:")
                print("[OSManualOTA]    OSManifestLoader.indexVersionToken: '\(versions["indexVersionToken"] ?? "error")'")
                print("[OSManualOTA]    localStorage.os_manual_ota_current_version: '\(versions["localStorage"] ?? "error")'")
            } else {
                print("[OSManualOTA] ⚠️ Could not parse JavaScript version data")
            }

            completion()
        }
    }
}
