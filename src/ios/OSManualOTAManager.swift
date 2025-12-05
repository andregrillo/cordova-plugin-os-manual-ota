//
//  OSManualOTAManager.swift
//  OutSystems Manual OTA Plugin
//
//  Main manager class for manual OTA updates
//

import Foundation
import UIKit
import WebKit
import ObjectiveC

@objc public class OSManualOTAManager: NSObject {

    // MARK: - Singleton
    @objc public static let shared = OSManualOTAManager()

    // MARK: - Properties
    private var configuration: OSUpdateConfiguration?
    private var currentStatus: OSUpdateStatus = .notAvailable
    private var isDownloading = false
    private var downloadCancelled = false

    // Callback handlers
    private var progressHandler: ((Int, Int, Int) -> Void)?
    private var errorHandler: ((String) -> Void)?

    // Storage
    private let defaults = UserDefaults.standard

    // MARK: - Initialization
    private override init() {
        super.init()
        loadConfiguration()
        checkForCrashOnLastUpdate()

        // Note: No need to check for pending swaps anymore
        // Cache swaps happen immediately after download completes
    }

    /// Called when app enters foreground - checks for pending cache swaps
    @objc private func appWillEnterForeground() {
        checkAndApplyPendingSwap()
    }

    /// Checks if there's a pending cache swap from background download and applies it
    private func checkAndApplyPendingSwap() {
        guard let pendingVersion = defaults.string(forKey: OSStorageKey.pendingSwapVersion) else {
            return // No pending swap
        }

        print("🔄 Detected pending cache swap for version: \(pendingVersion)")

        // Get the manifest for this version
        guard let config = configuration else {
            print("❌ Cannot apply pending swap: configuration not loaded")
            return
        }

        // Fetch manifest and swap
        Task {
            do {
                // Fetch the latest manifest from server
                let manifest = try await getModuleManifest()

                // Verify it matches our pending version
                if manifest.versionToken != pendingVersion {
                    print("⚠️ Warning: Pending version (\(pendingVersion)) doesn't match latest manifest (\(manifest.versionToken))")
                    print("   This could mean a newer version is available. Proceeding with pending swap anyway.")
                }

                try swapCacheToVersion(pendingVersion, manifest: manifest)

                // Clear pending swap flags
                defaults.removeObject(forKey: OSStorageKey.pendingSwapVersion)
                defaults.removeObject(forKey: OSStorageKey.pendingSwapTimestamp)

                print("✅ Pending cache swap completed successfully")
            } catch {
                print("❌ Failed to apply pending swap: \(error.localizedDescription)")
                // Leave the pending flags in place to retry next time
            }
        }
    }

    // MARK: - Configuration
    @objc public func configure(baseURL: String, hostname: String, applicationPath: String, currentVersion: String? = nil) {
        print("[OSManualOTA] 🔧 configure() called")
        print("[OSManualOTA]    baseURL: \(baseURL)")
        print("[OSManualOTA]    hostname: \(hostname)")
        print("[OSManualOTA]    applicationPath: \(applicationPath)")
        print("[OSManualOTA]    currentVersion from JS: \(currentVersion ?? "nil")")

        // Strip leading slash from applicationPath to match OutSystems automatic OTA
        // Automatic OTA uses "OTATest" but JavaScript might pass "/OTATest"
        let normalizedAppPath = applicationPath.hasPrefix("/") ? String(applicationPath.dropFirst()) : applicationPath
        print("[OSManualOTA]    normalized applicationPath: \(normalizedAppPath)")

        self.configuration = OSUpdateConfiguration(
            baseURL: baseURL,
            hostname: hostname,
            applicationPath: normalizedAppPath
        )
        saveConfiguration()

        // If JavaScript provided current version, use it directly
        if let version = currentVersion, !version.isEmpty {
            print("[OSManualOTA] ✅ Setting current version from JavaScript: '\(version)'")
            saveCurrentVersion(version)
            print("[OSManualOTA] 📝 Saved to UserDefaults, verifying: '\(getCurrentVersion())'")
        } else {
            print("[OSManualOTA] ⚠️ No currentVersion from JavaScript, trying OutSystems cache...")
            // Otherwise try to initialize from OutSystems cache
            initializeCurrentVersionIfNeeded()
        }

        print("[OSManualOTA] 🔧 configure() complete. Final currentVersion: '\(getCurrentVersion())'")
    }

    private func initializeCurrentVersionIfNeeded() {
        // Only initialize if we don't have a current version stored yet
        let storedVersion = defaults.string(forKey: OSStorageKey.currentVersion)

        if storedVersion == nil || storedVersion == "unknown" {
            print("[OSManualOTA] Initializing current version from OutSystems cache...")
            print("[OSManualOTA] Current stored version: \(storedVersion ?? "nil")")

            // Get the running version from OutSystems cache
            if let appCache = getOutSystemsCache() {
                print("[OSManualOTA] ✅ Got OSApplicationCache")

                if let runningFrame = appCache.getCurrentRunningFrame() {
                    let version = runningFrame.versionToken
                    print("[OSManualOTA] ✅ Found running version: \(version)")
                    saveCurrentVersion(version)
                } else {
                    print("[OSManualOTA] ❌ getCurrentRunningFrame() returned nil")
                }
            } else {
                print("[OSManualOTA] ❌ getOutSystemsCache() returned nil - cache not available yet")
                print("[OSManualOTA] NOTE: Version will be initialized on first checkForUpdates() call")
            }
        } else {
            print("[OSManualOTA] Current version already initialized: \(storedVersion ?? "unknown")")
        }
    }

    private func loadConfiguration() {
        // Try to load from app info or defaults
        if let baseURL = getBaseURLFromApp(),
           let hostname = getHostnameFromApp(),
           let appPath = getApplicationPathFromApp() {
            self.configuration = OSUpdateConfiguration(
                baseURL: baseURL,
                hostname: hostname,
                applicationPath: appPath
            )
        }
    }

    private func saveConfiguration() {
        guard let config = configuration else { return }
        defaults.set(config.baseURL, forKey: "os_manual_ota_base_url")
        defaults.set(config.hostname, forKey: "os_manual_ota_hostname")
        defaults.set(config.applicationPath, forKey: "os_manual_ota_app_path")
    }

    // MARK: - Version Debugging Helper
    private func logAllVersionSources() {
        print("[OSManualOTA] ========================================")
        print("[OSManualOTA] 🔍 COMPREHENSIVE VERSION DEBUG")
        print("[OSManualOTA] ========================================")

        // 1. Plugin's stored version in UserDefaults
        let pluginVersion = defaults.string(forKey: OSStorageKey.currentVersion) ?? "nil"
        print("[OSManualOTA] 📱 Plugin (UserDefaults): '\(pluginVersion)'")

        // 2. Plugin's getCurrentVersion() (with validation)
        let validatedVersion = getCurrentVersion()
        print("[OSManualOTA] 📱 Plugin (validated):    '\(validatedVersion)'")

        // 3. OutSystems cache versions
        if let appCache = getOutSystemsCache() {
            print("[OSManualOTA] ✅ OutSystems Cache accessible")

            // 3a. Running frame version token
            if let runningFrame = appCache.getCurrentRunningFrame() {
                let runningVersion = runningFrame.versionToken ?? "nil"
                let runningStatus = runningFrame.status.rawValue
                let runningPreBundle = runningFrame.preBundle
                print("[OSManualOTA] 🏃 Running Frame versionToken: '\(runningVersion)'")
                print("[OSManualOTA]    Running Frame status: \(runningStatus)")
                print("[OSManualOTA]    Running Frame preBundle: \(runningPreBundle)")
            } else {
                print("[OSManualOTA] ⚠️  getCurrentRunningFrame() returned nil")
            }

            // 3b. Cache version (from getCurrentCacheVersion method)
            let cacheVersion = appCache.getCurrentCacheVersion() ?? "nil"
            print("[OSManualOTA] 💾 getCurrentCacheVersion(): '\(cacheVersion)'")

            // 3c. Check prebundle frame if exists
            if let preBundle = appCache.getPreBundleFrame() {
                let preBundleVersion = preBundle.versionToken ?? "nil"
                print("[OSManualOTA] 📦 PreBundle Frame version: '\(preBundleVersion)'")
            } else {
                print("[OSManualOTA] 📦 No prebundle frame")
            }
        } else {
            print("[OSManualOTA] ❌ getOutSystemsCache() returned nil - cache not ready")
        }

        // 4. Check localStorage version (what JavaScript has)
        print("[OSManualOTA] 📝 localStorage value: (will check from JavaScript)")

        print("[OSManualOTA] ========================================")
    }

    // MARK: - Check for Updates
    @objc public func checkForUpdates(completion: @escaping (Bool, String?, Error?) -> Void) {
        guard let config = configuration else {
            completion(false, nil, OTAError.invalidConfiguration)
            return
        }

        // Try to initialize version if not set yet (fallback if configure was too early)
        initializeCurrentVersionIfNeeded()

        currentStatus = .checking

        Task {
            do {
                // DEBUG: Log all version sources BEFORE doing anything
                print("[OSManualOTA] 🔍 Checking for updates...")
                logAllVersionSources()

                let latestVersion = try await getLatestVersion()
                print("[OSManualOTA] 🌐 Server has version: '\(latestVersion)'")

                var currentVersion = getCurrentVersion()

                // IMPORTANT: Sync with actual running version from OutSystems cache
                // This handles the case where OutSystems loaded a new OTA version
                // but our plugin doesn't know about it yet
                print("[OSManualOTA] 🔄 Attempting to sync with OutSystems running version...")
                if let appCache = getOutSystemsCache() {
                    print("[OSManualOTA] ✅ Got OutSystems cache")
                    if let runningFrame = appCache.getCurrentRunningFrame() {
                        let actualRunningVersion = runningFrame.versionToken
                        print("[OSManualOTA] ✅ Got running frame with version: '\(actualRunningVersion)'")
                        if actualRunningVersion != currentVersion {
                            print("[OSManualOTA] 🔄 Detected version mismatch!")
                            print("[OSManualOTA]    Stored: '\(currentVersion)'")
                            print("[OSManualOTA]    Actually running: '\(actualRunningVersion)'")
                            print("[OSManualOTA] ✅ Updating to actual running version")
                            saveCurrentVersion(actualRunningVersion)
                            currentVersion = actualRunningVersion
                        } else {
                            print("[OSManualOTA] ✅ Versions already match - no sync needed")
                        }
                    } else {
                        print("[OSManualOTA] ⚠️ getCurrentRunningFrame() returned nil")
                    }
                } else {
                    print("[OSManualOTA] ⚠️ getOutSystemsCache() returned nil - cache not ready")
                }

                print("[OSManualOTA] 🔍 Version comparison:")
                print("[OSManualOTA]    Current: '\(currentVersion)'")
                print("[OSManualOTA]    Latest:  '\(latestVersion)'")
                print("[OSManualOTA]    Match: \(latestVersion == currentVersion)")

                // If still unknown, use the latest version as current (first time)
                if currentVersion == "unknown" {
                    print("[OSManualOTA] ⚠️ First time check - setting current version to: \(latestVersion)")
                    saveCurrentVersion(latestVersion)
                    currentVersion = latestVersion
                    print("[OSManualOTA] 📝 After update - currentVersion is now: '\(currentVersion)'")
                    print("[OSManualOTA] 📝 Saved to UserDefaults, verifying: '\(getCurrentVersion())'")
                }

                // Update last check timestamp
                defaults.set(Date(), forKey: OSStorageKey.lastUpdateCheck)

                print("[OSManualOTA] 🔍 Final comparison before return:")
                print("[OSManualOTA]    latestVersion: '\(latestVersion)'")
                print("[OSManualOTA]    currentVersion: '\(currentVersion)'")
                print("[OSManualOTA]    Are they equal? \(latestVersion == currentVersion)")
                print("[OSManualOTA]    Are they NOT equal? \(latestVersion != currentVersion)")

                if latestVersion != currentVersion {
                    currentStatus = .available(version: latestVersion)
                    print("[OSManualOTA] ✅ Update available!")
                    completion(true, latestVersion, nil)
                } else {
                    currentStatus = .notAvailable
                    print("[OSManualOTA] ✅ No update - versions match")
                    completion(false, currentVersion, nil)
                }
            } catch {
                currentStatus = .failed(error: error)
                completion(false, nil, error)
            }
        }
    }

    // MARK: - Download Update
    @objc public func downloadUpdate(
        progressHandler: ((Int, Int, Int) -> Void)? = nil,
        errorHandler: ((String) -> Void)? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard let config = configuration else {
            errorHandler?("Invalid configuration")
            completion(false)
            return
        }

        guard !isDownloading else {
            errorHandler?("Download already in progress")
            completion(false)
            return
        }

        self.progressHandler = progressHandler
        self.errorHandler = errorHandler
        self.isDownloading = true
        self.downloadCancelled = false

        Task {
            let startTime = Date()

            do {
                // 1. Get latest version
                let latestVersion = try await getLatestVersion()
                let currentVersion = getCurrentVersion()

                guard latestVersion != currentVersion else {
                    throw OTAError.noUpdateAvailable
                }

                // 2. Check network conditions
                try checkNetworkConditions()

                // 3. Get manifest with file hashes
                let manifest = try await getModuleManifest()

                // 4. Compare with current hashes to find changed files
                let changedFiles = getChangedFiles(newHashes: manifest.urlVersions)

                guard !changedFiles.isEmpty else {
                    throw OTAError.noUpdateAvailable
                }

                // 5. Download changed files using OutSystems infrastructure
                let success = try await downloadChangedFiles(
                    changedFiles: changedFiles,
                    manifest: manifest,
                    version: latestVersion
                )

                if success && !downloadCancelled {
                    // 6. Save new version and hashes AFTER successful download
                    //    Note: Patched files were skipped from download, so our modifications remain intact
                    //    Cache swap will happen either:
                    //    - When app enters foreground (if downloaded in background)
                    //    - Immediately if already in foreground (handled by checkAndApplyPendingSwap)
                    saveDownloadedVersion(latestVersion)
                    saveAssetHashes(manifest.urlVersions)

                    print("✅ Download completed - update marked for cache swap")

                    // 8. Log metrics
                    let duration = Date().timeIntervalSince(startTime)
                    logUpdateMetrics(
                        checkDuration: 0,
                        downloadDuration: duration,
                        downloadSize: 0,
                        filesDownloaded: changedFiles.count,
                        filesSkipped: manifest.urlVersions.count - changedFiles.count,
                        filesFailed: 0,
                        success: true,
                        errorMessage: nil,
                        triggerMethod: "manual"
                    )

                    currentStatus = .downloaded
                    isDownloading = false
                    completion(true)
                } else {
                    throw downloadCancelled ? OTAError.cancelled : OTAError.downloadFailed("Unknown error")
                }

            } catch {
                currentStatus = .failed(error: error)
                isDownloading = false
                errorHandler?(error.localizedDescription)
                completion(false)
            }
        }
    }

    // MARK: - Apply Update
    @objc public func applyUpdate(completion: @escaping (Bool, Error?) -> Void) {
        guard let downloadedVersion = getDownloadedVersion() else {
            completion(false, OTAError.noUpdateAvailable)
            return
        }

        // Save current version as previous (for rollback)
        let currentVersion = getCurrentVersion()
        savePreviousVersion(currentVersion)

        // Mark the downloaded version as current
        saveCurrentVersion(downloadedVersion)

        // Set flag to detect crash on next launch
        setCrashDetectionFlag()

        // In OutSystems, the cache swap happens automatically on next app launch
        // We just need to ensure the version is updated
        completion(true, nil)
    }

    // MARK: - Rollback
    @objc public func rollbackToPreviousVersion(completion: @escaping (Bool, Error?) -> Void) {
        guard let previousVersion = getPreviousVersion() else {
            completion(false, OTAError.rollbackFailed("No previous version available"))
            return
        }

        // Use OutSystems cache rollback if available
        if let osCache = getOutSystemsCache() {
            osCache.rollbackToPreviousVersion()
        }

        // Update version info
        saveCurrentVersion(previousVersion)
        clearDownloadedVersion()

        // Clear crash detection flag
        clearCrashDetectionFlag()

        completion(true, nil)
    }

    // MARK: - Cancel Download
    @objc public func cancelDownload() {
        downloadCancelled = true

        // Cancel OutSystems OSCacheResources download
        if let cacheResources = currentCacheResources {
            cacheResources.cancelDownload()
            print("⚠️ Download cancelled")
        }

        currentCacheResources = nil
    }

    // MARK: - Version Management
    @objc public func getCurrentVersionInfo(completion: @escaping ([String: Any]?) -> Void) {
        let currentVersion = getCurrentVersion()
        let downloadedVersion = getDownloadedVersion()
        let previousVersion = getPreviousVersion()
        let lastCheck = defaults.object(forKey: OSStorageKey.lastUpdateCheck) as? Date

        let info: [String: Any] = [
            "currentVersion": currentVersion,
            "downloadedVersion": downloadedVersion ?? "",
            "previousVersion": previousVersion ?? "",
            "lastUpdateCheck": lastCheck?.timeIntervalSince1970 ?? 0,
            "isUpdateDownloaded": downloadedVersion != nil,
            "isDownloading": isDownloading
        ]

        completion(info)
    }

    // MARK: - OTA Blocking Control
    @objc public func setOTABlockingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: OSStorageKey.otaBlockingEnabled)

        // Also sync to JavaScript side via notification
        // The JavaScript hook checks localStorage for the blocking state
        NotificationCenter.default.post(
            name: .otaBlockingStatusChanged,
            object: nil,
            userInfo: ["enabled": enabled]
        )

        // Trigger JavaScript update
        DispatchQueue.main.async {
            self.syncBlockingStateToJavaScript(enabled)
        }

        print("✅ OTA blocking \(enabled ? "enabled" : "disabled")")
    }

    @objc public func isOTABlockingEnabled() -> Bool {
        return defaults.bool(forKey: OSStorageKey.otaBlockingEnabled)
    }

    // Sync blocking state to JavaScript localStorage
    private func syncBlockingStateToJavaScript(_ enabled: Bool) {
        // This will be called from the plugin to update localStorage
        // The JavaScript hook checks localStorage.getItem('os_manual_ota_blocking_enabled')
        let js = """
        (function() {
            localStorage.setItem('os_manual_ota_blocking_enabled', '\(enabled ? "true" : "false")');
            console.log('[OSManualOTA] Blocking state updated: \(enabled ? "enabled" : "disabled")');
        })();
        """

        // This would need a WebView reference - will be handled via plugin
        // For now, the plugin will handle this via JavaScript callback
    }

    // MARK: - Splash Screen Bypass Control
    @objc public func setSplashBypassEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: OSStorageKey.splashBypassEnabled)
        print("💨 [OSManualOTA] Splash bypass \(enabled ? "enabled" : "disabled")")

        // Post notification for UI updates if needed
        NotificationCenter.default.post(
            name: .splashBypassStatusChanged,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    @objc public func isSplashBypassEnabled() -> Bool {
        return defaults.bool(forKey: OSStorageKey.splashBypassEnabled)
    }

    // MARK: - Network API Calls
    private func getLatestVersion() async throws -> String {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        let urlString = "\(config.baseURL)/moduleservices/moduleversioninfo"
        guard let url = URL(string: urlString) else {
            throw OTAError.versionCheckFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("native", forHTTPHeaderField: "OutSystems-client-env")
        request.timeoutInterval = config.downloadTimeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OTAError.versionCheckFailed("HTTP error")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let versionToken = json["versionToken"] as? String else {
            throw OTAError.versionCheckFailed("Invalid response format")
        }

        return versionToken
    }

    private func getModuleManifest() async throws -> OSModuleManifest {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        let urlString = "\(config.baseURL)/moduleservices/moduleinfo"
        guard let url = URL(string: urlString) else {
            throw OTAError.manifestFetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("native", forHTTPHeaderField: "OutSystems-client-env")
        request.timeoutInterval = config.downloadTimeout

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OTAError.manifestFetchFailed("HTTP error")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let manifestDict = json["manifest"] as? [String: Any],
              let versionToken = manifestDict["versionToken"] as? String,
              let urlVersions = manifestDict["urlVersions"] as? [String: String] else {
            throw OTAError.manifestFetchFailed("Invalid response format")
        }

        let manifest = OSModuleManifest(
            versionToken: versionToken,
            urlVersions: urlVersions,
            urlMappings: manifestDict["urlMappings"] as? [String: String],
            urlMappingsNoCache: manifestDict["urlMappingsNoCache"] as? [String: String]
        )

        return manifest
    }

    // MARK: - File Comparison & Download
    private func getChangedFiles(newHashes: [String: String]) -> [String: String] {
        guard let savedHashesData = defaults.data(forKey: OSStorageKey.assetHashes),
              let oldHashes = try? JSONDecoder().decode([String: String].self, from: savedHashesData) else {
            // First run, all files are new
            return newHashes
        }

        // Return only files where the hash has changed
        return newHashes.filter { key, value in
            oldHashes[key] != value
        }
    }

    // MARK: - Cache Directory Management
    private func ensureCacheDirectoryExists(forVersion version: String) throws {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        // Get the cache base directory path
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OTAError.downloadFailed("Could not access Application Support directory")
        }

        // Build the cache path structure like OutSystems does:
        // .../Application Support/OSNativeCache/{hash(hostname/application)}/
        // This matches the logic in OSNativeCache.m:1045-1050
        let cacheBaseDir = appSupportDir.appendingPathComponent("OSNativeCache")

        // Generate the same hash that OutSystems uses via Objective-C helper
        // This ensures we get the same NSString hash value, not Swift's hashValue
        let cacheKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        let cacheAppDir = cacheBaseDir.appendingPathComponent(cacheKey)

        // Create directories if they don't exist
        do {
            if !fileManager.fileExists(atPath: cacheBaseDir.path) {
                try fileManager.createDirectory(at: cacheBaseDir, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created cache base directory: \(cacheBaseDir.path)")
            }

            if !fileManager.fileExists(atPath: cacheAppDir.path) {
                try fileManager.createDirectory(at: cacheAppDir, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created cache app directory: \(cacheAppDir.path)")
            }
        } catch {
            print("❌ Failed to create cache directories: \(error.localizedDescription)")
            throw OTAError.downloadFailed("Failed to create cache directories: \(error.localizedDescription)")
        }
    }

    private func downloadChangedFiles(
        changedFiles: [String: String],
        manifest: OSModuleManifest,
        version: String
    ) async throws -> Bool {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        // Ensure cache directory exists before downloading
        try ensureCacheDirectoryExists(forVersion: version)

        // Report initial progress
        let totalFiles = manifest.urlVersions.count
        let changedCount = changedFiles.count
        let skippedFiles = totalFiles - changedCount
        progressHandler?(0, changedCount, skippedFiles)

        // Files we patch and should skip from download (keep our patched versions)
        let patchedFiles = [
            "/scripts/OutSystemsManifestLoader.js",
            "/scripts/OutSystemsUI.Private.ApplicationLoadEvents.mvc.js"
        ]

        // Prepare resource list in OutSystems format
        // Format: ["path?hash", "path2?hash2", ...]
        // Skip patched files - we'll keep using our modified versions
        var resourceList = NSMutableArray()
        var skippedPatchedFiles = 0
        for (path, hash) in manifest.urlVersions {
            // Skip files that we've patched
            var shouldSkip = false
            for patchedFile in patchedFiles {
                if path.contains(patchedFile) {
                    shouldSkip = true
                    skippedPatchedFiles += 1
                    print("⏭️  Skipping patched file from download: \(path)")
                    break
                }
            }

            if !shouldSkip {
                // Check if hash already starts with '?' to avoid double question marks
                let resourcePath: String
                if hash.hasPrefix("?") {
                    resourcePath = "\(path)\(hash)"
                } else {
                    resourcePath = "\(path)?\(hash)"
                }
                resourceList.add(resourcePath)
            }
        }

        if skippedPatchedFiles > 0 {
            print("✅ Skipped \(skippedPatchedFiles) patched file(s) from download - keeping our modifications")
        }

        // Prepare URL mappings (if any)
        let urlMappings = NSMutableDictionary()
        if let mappings = manifest.urlMappings {
            for (key, value) in mappings {
                urlMappings.setValue(value, forKey: key)
            }
        }

        // Prepare URL mappings no cache (if any)
        let urlMappingsNoCache = NSMutableDictionary()
        if let mappings = manifest.urlMappingsNoCache {
            for (key, value) in mappings {
                urlMappingsNoCache.setValue(value, forKey: key)
            }
        }

        // Use continuation to bridge async/await with OutSystems completion blocks
        return try await withCheckedThrowingContinuation { continuation in
            // Track progress
            var downloadedFiles = 0
            var errorOccurred = false
            var cacheResourcesRef: OSCacheResources?

            // Progress handler
            let downloadProgressBlock: DownloadProgressBlock = { [weak self] initial, loaded, total in
                guard let self = self else { return }

                if let loaded = loaded, let total = total {
                    downloadedFiles = loaded.intValue
                    let totalFilesInt = total.intValue
                    let skipped = totalFilesInt - changedCount

                    self.progressHandler?(downloadedFiles, changedCount, skipped)
                }
            }

            // Error handler
            let downloadErrorBlock: DownloadErrorBlock = { [weak self] errorMessage in
                guard let self = self else { return }

                print("❌ Download error: \(errorMessage ?? "unknown")")
                self.errorHandler?(errorMessage ?? "Download error")
                errorOccurred = true
            }

            // Finish handler
            let downloadFinishBlock: DownloadFinishBlock = { [weak self] success in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }

                if self.downloadCancelled {
                    continuation.resume(returning: false)
                } else if errorOccurred || !success {
                    continuation.resume(throwing: OTAError.downloadFailed("Download failed"))
                } else {
                    // Register the downloaded cache frame with OutSystems cache system
                    guard let cacheResources = cacheResourcesRef else {
                        continuation.resume(throwing: OTAError.downloadFailed("Cache resources not available"))
                        return
                    }

                    do {
                        try self.registerCacheFrame(cacheResources, version: version)

                        // Swap cache IMMEDIATELY - don't defer!
                        // This ensures updates are ready instantly when user opens app
                        print("🔄 Swapping cache immediately after download...")
                        try self.swapCacheToVersion(version, manifest: manifest)

                        // Update our stored current version
                        self.saveCurrentVersion(version)

                        print("✅ Cache swap completed! App will use new version on next launch.")

                        // 🔧 UPDATE: Store new version in localStorage for JavaScript to use
                        print("🔧 Updating localStorage with new version token...")
                        self.updateVersionInLocalStorage(newVersion: version)

                        // 🔧 CRITICAL: Patch the cached OutSystemsManifestLoader.js to add our override logic
                        print("🔧 Patching cached OutSystemsManifestLoader.js...")
                        self.patchCachedManifestLoader()

                        // 🔄 CRITICAL: Call switchToVersion to apply the update NOW (like automatic OTA does)
                        // This is what makes the automatic OTA work - it switches to the new version immediately
                        print("🔄 Calling switchToVersion to apply update immediately...")
                        if let cacheEngine = OSNativeCache.sharedInstance(),
                           let config = self.configuration {
                            // Call switchToVersion via Objective-C runtime
                            // Define the method signature that matches: -(void) switchToVersion:(NSString*)hostname application:(NSString*)application version:(NSString*)version
                            typealias SwitchToVersionFunc = @convention(c) (AnyObject, Selector, NSString, NSString, NSString) -> Void

                            let selector = NSSelectorFromString("switchToVersion:application:version:")
                            if let method = class_getInstanceMethod(object_getClass(cacheEngine), selector) {
                                let implementation = method_getImplementation(method)
                                let typedImplementation = unsafeBitCast(implementation, to: SwitchToVersionFunc.self)
                                typedImplementation(cacheEngine as AnyObject, selector, config.hostname as NSString, config.applicationPath as NSString, version as NSString)
                                print("✅ switchToVersion called successfully")
                            } else {
                                print("⚠️  Could not find switchToVersion method")
                            }
                        } else {
                            print("⚠️  Could not get OSNativeCache sharedInstance or configuration for switchToVersion")
                        }

                        continuation.resume(returning: true)
                    } catch {
                        print("❌ Failed to register or swap cache: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Create URLSession getter block
            let sessionGetter: DownloadSession = {
                return URLSession.shared
            }

            // Create OSCacheResources instance
            let cacheResources = OSCacheResources(
                forHostname: config.hostname,
                application: config.applicationPath,
                withVersion: version,
                forPrebundle: false,
                urlSessionGetter: sessionGetter,
                onProgressHandler: downloadProgressBlock,
                onErrorHandler: downloadErrorBlock,
                onFinishHandler: downloadFinishBlock
            )

            // Store reference for finish handler
            cacheResourcesRef = cacheResources

            // Get or create application cache
            // Note: In a real integration, you'd get this from OSNativeCache
            // For now, we create a minimal cache pool
            let resourcePool = NSMutableDictionary()

            // Populate cache entries (this will compare hashes and only download changed files)
            cacheResources.populateCacheEntries(
                forResourcePool: resourcePool,
                prebundleEntries: nil,
                resourceList: resourceList,
                urlMaps: urlMappings,
                urlMapsNoCache: urlMappingsNoCache
            )

            // Start download using OutSystems infrastructure
            print("🚀 Starting download of \(changedCount) changed files (out of \(totalFiles) total)")
            cacheResources.startDownload()

            // Store reference to cancel if needed
            DispatchQueue.main.async { [weak self] in
                self?.currentCacheResources = cacheResources
            }
        }
    }

    // Store current download instance for cancellation
    private var currentCacheResources: OSCacheResources?

    // MARK: - Storage Helpers
    internal func getCurrentVersion() -> String {
        let storedVersion = defaults.string(forKey: OSStorageKey.currentVersion) ?? "unknown"

        // Validate the stored version - reject invalid values
        if storedVersion == "false" || storedVersion == "true" {
            print("[OSManualOTA] ⚠️ Invalid version '\(storedVersion)' in UserDefaults - clearing it")
            defaults.removeObject(forKey: OSStorageKey.currentVersion)
            return "unknown"
        }

        return storedVersion
    }

    internal func saveCurrentVersion(_ version: String) {
        defaults.set(version, forKey: OSStorageKey.currentVersion)
    }

    private func getPreviousVersion() -> String? {
        return defaults.string(forKey: OSStorageKey.previousVersion)
    }

    private func savePreviousVersion(_ version: String) {
        defaults.set(version, forKey: OSStorageKey.previousVersion)
    }

    private func getDownloadedVersion() -> String? {
        return defaults.string(forKey: OSStorageKey.downloadedVersion)
    }

    private func saveDownloadedVersion(_ version: String) {
        defaults.set(version, forKey: OSStorageKey.downloadedVersion)
    }

    private func clearDownloadedVersion() {
        defaults.removeObject(forKey: OSStorageKey.downloadedVersion)
    }

    private func saveAssetHashes(_ hashes: [String: String]) {
        if let data = try? JSONEncoder().encode(hashes) {
            defaults.set(data, forKey: OSStorageKey.assetHashes)
        }
    }

    // MARK: - Cache Frame Management

    /// Registers a downloaded cache frame with the OutSystems cache system
    /// This makes the frame discoverable for cache swapping
    private func registerCacheFrame(_ cacheResources: OSCacheResources, version: String) throws {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        print("📝 Registering cache frame for version: \(version)")

        // Get the shared OSNativeCache instance
        guard let cacheInstance = OSNativeCache.sharedInstance() as? OSNativeCache else {
            throw OTAError.downloadFailed("OSNativeCache not available")
        }

        // Set current application context
        cacheInstance.setCurrentApplication(config.hostname, application: config.applicationPath)

        // Get the application cache
        let appKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        guard let applicationEntries = cacheInstance.applicationEntries(),
              let appCache = applicationEntries.object(forKey: appKey) as? OSApplicationCache else {
            throw OTAError.downloadFailed("Application cache not found for key: \(appKey)")
        }

        // Add the cache frame to the application cache
        appCache.addFrame(cacheResources)
        print("✅ Cache frame registered successfully")
    }

    // MARK: - Cache Swapping

    /// Swaps the OutSystems cache to make the downloaded version active
    /// This is the critical step that makes OutSystems load the new version on next app start
    private func swapCacheToVersion(_ version: String, manifest: OSModuleManifest) throws {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        print("🔄 Swapping cache to version: \(version)")

        // Get the shared OSNativeCache instance - cast to proper type
        guard let cacheInstance = OSNativeCache.sharedInstance() as? OSNativeCache else {
            throw OTAError.downloadFailed("OSNativeCache not available")
        }

        // Set current application context
        cacheInstance.setCurrentApplication(config.hostname, application: config.applicationPath)

        // Get the application cache
        let appKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        guard let applicationEntries = cacheInstance.applicationEntries(),
              let appCache = applicationEntries.object(forKey: appKey) as? OSApplicationCache else {
            throw OTAError.downloadFailed("Application cache not found for key: \(appKey)")
        }

        // Find the cache frame for our downloaded version
        guard let downloadedFrame = appCache.getFrameForVersion(version) else {
            throw OTAError.downloadFailed("Downloaded cache frame not found for version: \(version)")
        }

        print("📦 Found cache frame for version \(version)")
        print("   Status: \(downloadedFrame.status.rawValue)")
        if let entries = downloadedFrame.cacheEntries {
            print("   Cache entries count: \(entries.count)")
        }

        // Set the downloaded frame as ongoing cache resources
        cacheInstance.setOngoingCacheResources(downloadedFrame)

        // Change cache status to UPDATE_READY (required for swapCache to work)
        // OSCacheStatusUpdateReady = 4
        cacheInstance.change(OSCacheStatus(rawValue: 4)!)
        print("✅ Cache status set to UPDATE_READY")

        // Perform the cache swap
        let swapSuccess = cacheInstance.swapCache()

        if !swapSuccess {
            throw OTAError.downloadFailed("swapCache() returned false - check cache status and resource validation")
        }

        print("✅ Cache swap completed successfully")

        // 🔧 CRITICAL FIX: Update urlMappings in application cache to point to new version
        // swapCache() deliberately skips resourceMapping entries (urlMappings)
        // We need to manually update these entries in appCache._cacheEntries
        print("🔧 Updating urlMappings in application cache for new version...")

        var mappingsUpdated = 0

        // Process urlMappings (with cache)
        if let urlMappings = manifest.urlMappings {
            for (mappingKey, resourceUrl) in urlMappings {
                // Get the versioned URL from urlVersions
                if let resourceVersion = manifest.urlVersions[resourceUrl] {
                    let versionedUrl = "\(resourceUrl)\(resourceVersion)"

                    // Create or update cache entry for this mapping
                    let selector = NSSelectorFromString("addCacheEntryForURL:withResourceMapping:")
                    if appCache.responds(to: selector) {
                        _ = appCache.perform(selector, with: mappingKey, with: versionedUrl)
                        mappingsUpdated += 1
                        print("   ✅ Updated mapping: \(mappingKey) -> \(versionedUrl)")
                    }
                }
            }
        }

        // Process urlMappingsNoCache
        if let urlMappingsNoCache = manifest.urlMappingsNoCache {
            for (mappingKey, resourceUrl) in urlMappingsNoCache {
                // Get the versioned URL from urlVersions
                if let resourceVersion = manifest.urlVersions[resourceUrl] {
                    let versionedUrl = "\(resourceUrl)\(resourceVersion)"

                    // Create or update cache entry for this mapping
                    let selector = NSSelectorFromString("addCacheEntryForURL:withResourceMapping:")
                    if appCache.responds(to: selector) {
                        _ = appCache.perform(selector, with: mappingKey, with: versionedUrl)
                        mappingsUpdated += 1
                        print("   ✅ Updated no-cache mapping: \(mappingKey) -> \(versionedUrl)")
                    }
                }
            }
        }

        print("✅ urlMappings rebuilt for new version \(version) (\(mappingsUpdated) mappings updated)")

        // CRITICAL: Write the manifest to disk to persist the swap
        // swapCache() should already call writeCacheManifest, but we'll call it explicitly
        // to ensure the new version is persisted to disk
        // Note: Objective-C method is writeCacheManifest, but Swift bridges it as writeManifest

        // Get the running version token BEFORE writing manifest
        let runningFrameBeforeWrite = appCache.getCurrentRunningFrame()
        let runningVersionBeforeWrite = runningFrameBeforeWrite?.versionToken ?? "nil"
        print("📝 About to write manifest. Running version token: \(runningVersionBeforeWrite)")

        cacheInstance.writeManifest()
        print("✅ Cache manifest explicitly written to disk")

        // 🔍 COMPREHENSIVE MANIFEST VERIFICATION
        print("\n🔍 === MANIFEST VERIFICATION START ===")

        // 1. Get the manifest file path
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        if let appSupportDir = paths.first {
            let manifestPath = (appSupportDir as NSString).appendingPathComponent("OSNativeCache/OSCacheManifest.plist")
            print("📂 Manifest file path: \(manifestPath)")

            let fileManager = FileManager.default

            // 2. Check if file exists
            if fileManager.fileExists(atPath: manifestPath) {
                print("✅ Manifest file EXISTS")

                // 3. Get file attributes
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: manifestPath)
                    let fileSize = attributes[.size] as? Int ?? 0
                    let modDate = attributes[.modificationDate] as? Date ?? Date()
                    let permissions = attributes[.posixPermissions] as? Int ?? 0

                    print("   File size: \(fileSize) bytes")
                    print("   Modified: \(modDate)")
                    print("   Permissions: \(String(format: "%o", permissions))")
                } catch {
                    print("⚠️  Could not read file attributes: \(error)")
                }

                // 4. Read the manifest file back
                if let manifestDict = NSDictionary(contentsOfFile: manifestPath) {
                    print("✅ Successfully READ manifest file back")

                    // Debug: Print top-level keys
                    print("   Top-level keys in manifest: \(manifestDict.allKeys)")

                    // Debug: Check what cachedApplication actually is
                    if let cachedAppRaw = manifestDict["cachedApplication"] {
                        print("   📋 cachedApplication: \(cachedAppRaw) (Type: \(type(of: cachedAppRaw)))")
                    }

                    // Debug: Check cachedEntries - this should contain the actual cache data
                    if let cachedEntriesRaw = manifestDict["cachedEntries"] {
                        print("   📋 cachedEntries exists!")
                        print("   📋 Type: \(type(of: cachedEntriesRaw))")

                        // Try to access it as a dictionary
                        if let cachedEntries = cachedEntriesRaw as? NSDictionary {
                            print("   📋 cachedEntries keys: \(cachedEntries.allKeys)")

                            // Check if our app ID is in there
                            if let appCacheId = manifestDict["cachedApplication"] as? String {
                                if let appCache = cachedEntries[appCacheId] as? NSDictionary {
                                    print("   ✅ Found cache data for app: \(appCacheId)")
                                    print("   📋 App cache keys: \(appCache.allKeys)")

                                    // Now look for version token (note: key is "cachedVersion" not "CacheVersion")
                                    if let versionToken = appCache["cachedVersion"] as? String {
                                        print("   📌 cachedVersion in file: \(versionToken)")

                                        if versionToken == version {
                                            print("   ✅ ✅ ✅ VERSION TOKEN MATCHES! (\(version))")
                                        } else {
                                            print("   ❌ ❌ ❌ VERSION TOKEN MISMATCH!")
                                            print("      Expected: \(version)")
                                            print("      Found: \(versionToken)")
                                        }
                                    } else {
                                        print("   ❌ cachedVersion not found in app cache")
                                        print("   Available keys: \(appCache.allKeys)")
                                    }
                                } else {
                                    print("   ❌ App cache data not found for ID: \(appCacheId)")
                                }
                            }
                        }
                    } else {
                        print("   ⚠️  cachedEntries not found")
                    }

                    // OLD CODE - keeping for reference but this was wrong assumption
                    if false, let cachedApp = manifestDict["cachedApplication"] as? NSDictionary {
                        print("   ✅ Found cachedApplication entry as NSDictionary")

                        // Check the version token
                        if let versionToken = cachedApp["CacheVersion"] as? String {
                            print("   📌 CacheVersion in file: \(versionToken)")

                            if versionToken == version {
                                print("   ✅ VERSION TOKEN MATCHES! (\(version))")
                            } else {
                                print("   ❌ VERSION TOKEN MISMATCH!")
                                print("      Expected: \(version)")
                                print("      Found: \(versionToken)")
                            }
                        } else {
                            print("   ❌ CacheVersion key not found in cachedApplication!")
                            print("   cachedApplication keys: \(cachedApp.allKeys)")
                        }

                        // Check frames
                        if let frames = cachedApp["Frames"] as? NSArray {
                            print("   Cache frames in manifest: \(frames.count)")
                            for (index, frame) in frames.enumerated() {
                                if let frameDict = frame as? NSDictionary,
                                   let frameVersion = frameDict["VersionToken"] as? String {
                                    print("      Frame \(index): \(frameVersion)")
                                }
                            }
                        } else {
                            print("   ⚠️  No Frames array found")
                        }

                        // Check hostname and path
                        if let hostname = cachedApp["Hostname"] as? String,
                           let appPath = cachedApp["ApplicationPath"] as? String {
                            print("   Application: \(hostname)\(appPath)")
                        }
                    } else {
                        print("   ❌ cachedApplication key not found!")
                    }

                    // Also check nativeCacheVersion for reference
                    if let cacheVersion = manifestDict["nativeCacheVersion"] as? String {
                        print("   Native cache version: \(cacheVersion)")
                    }
                } else {
                    print("❌ FAILED to read manifest file back!")
                    print("   This suggests the file is corrupted or format is invalid")
                }
            } else {
                print("❌ Manifest file DOES NOT EXIST at path!")
                print("   This means writeManifest() did not create the file")

                // List what files DO exist in the OSNativeCache directory
                let cacheDir = (appSupportDir as NSString).appendingPathComponent("OSNativeCache")
                print("\n📁 Checking what exists in OSNativeCache directory:")
                print("   Directory path: \(cacheDir)")

                if fileManager.fileExists(atPath: cacheDir) {
                    print("   ✅ OSNativeCache directory EXISTS")

                    do {
                        let contents = try fileManager.contentsOfDirectory(atPath: cacheDir)
                        print("   Files in directory (\(contents.count)):")
                        for item in contents {
                            let itemPath = (cacheDir as NSString).appendingPathComponent(item)
                            let attrs = try? fileManager.attributesOfItem(atPath: itemPath)
                            let size = attrs?[.size] as? Int ?? 0
                            print("      - \(item) (\(size) bytes)")
                        }
                    } catch {
                        print("   ⚠️  Could not list directory contents: \(error)")
                    }
                } else {
                    print("   ❌ OSNativeCache directory DOES NOT EXIST!")
                }
            }
        } else {
            print("❌ Could not get Application Support directory")
        }

        print("🔍 === MANIFEST VERIFICATION END ===\n")

        // Verify the running version was actually updated
        if let newRunningFrame = appCache.getCurrentRunningFrame() {
            let runningVersion = newRunningFrame.versionToken
            print("   Running version after swap: \(runningVersion ?? "nil")")

            if runningVersion != version {
                print("⚠️  WARNING: Running version (\(runningVersion ?? "nil")) doesn't match downloaded version (\(version))")
            } else {
                print("   ✅ New version \(version) will load on next app start")
            }
        } else {
            print("⚠️  WARNING: Could not verify running version after swap")
        }

        // Also update our UserDefaults tracking
        saveCurrentVersion(version)
    }

    // MARK: - Plugin Patch Management
    // NOTE: Cache patching functions disabled - not needed for current implementation
    // These functions attempted to patch files in the cache but caused issues
    // The plugin now relies solely on the JavaScript hooks that patch files at runtime

    // MARK: - File Patching (Re-enabled for manual OTA)
    private func deletePatchedFilesFromCache(version: String, manifest: OSModuleManifest) throws {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("⚠️ Could not access app support directory")
            return
        }

        let cacheKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        let cacheDir = appSupportDir
            .appendingPathComponent("OSNativeCache")
            .appendingPathComponent(cacheKey)

        print("🔍 Looking for patched files in cache: \(cacheDir.path)")

        // Also check www directory (prebundle/initial files)
        guard let wwwDir = Bundle.main.resourceURL?.appendingPathComponent("www/scripts") else {
            print("⚠️ Could not access www directory")
            return
        }
        print("🔍 Also checking www directory: \(wwwDir.path)")

        guard fileManager.fileExists(atPath: cacheDir.path) else {
            print("ℹ️ Cache directory doesn't exist yet - nothing to delete")
            return
        }

        // File paths that we patch (from the manifest)
        let patchedFilePaths = [
            "/scripts/OutSystemsManifestLoader.js",
            "/scripts/OutSystemsUI.Private.ApplicationLoadEvents.mvc.js"
        ]

        // Scan ALL files in cache by content to find patched files
        // We can't rely on hash matching because patched files have different hashes
        do {
            let files = try fileManager.contentsOfDirectory(atPath: cacheDir.path)
            print("📁 Found \(files.count) files in cache directory")
            var deletedCount = 0

            // Scan every file and check content
            for fileName in files {
                let filePath = cacheDir.appendingPathComponent(fileName)

                // Only check text files (JS/CSS)
                guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                    continue
                }

                var shouldDelete = false
                var deleteReason = ""

                // Check if this is OutSystemsManifestLoader.js
                if content.contains("OutSystemsManifestLoader") && content.contains("function(e){") {
                    shouldDelete = true
                    deleteReason = "OutSystemsManifestLoader.js content"
                    print("🎯 Found OutSystemsManifestLoader.js in file \(fileName)")
                }
                // Check if this is ApplicationLoadEvents
                else if content.contains("ApplicationLoadEvents") && content.contains("MinimumDisplayTimeMs") {
                    shouldDelete = true
                    deleteReason = "ApplicationLoadEvents content"
                    print("🎯 Found ApplicationLoadEvents in file \(fileName)")
                }

                if shouldDelete {
                    do {
                        try fileManager.removeItem(at: filePath)
                        print("🗑️  Deleted: \(fileName) (\(deleteReason))")
                        deletedCount += 1
                    } catch {
                        print("⚠️ Failed to delete \(fileName): \(error.localizedDescription)")
                    }
                }
            }

            print("✅ Deleted \(deletedCount) cached file(s) from cache")

            // ALSO delete from www directory (prebundle) if files exist there
            // This is where OutSystems loads files from if they're not in cache yet
            if fileManager.fileExists(atPath: wwwDir.path) {
                let wwwManifestLoader = wwwDir.appendingPathComponent("OutSystemsManifestLoader.js")
                let wwwAppLoadEvents = wwwDir.appendingPathComponent("OutSystemsUI.Private.ApplicationLoadEvents.mvc.js")

                if fileManager.fileExists(atPath: wwwManifestLoader.path) {
                    do {
                        try fileManager.removeItem(at: wwwManifestLoader)
                        print("🗑️  Deleted www/OutSystemsManifestLoader.js")
                        deletedCount += 1
                    } catch {
                        print("⚠️ Failed to delete www/OutSystemsManifestLoader.js: \(error.localizedDescription)")
                    }
                }

                if fileManager.fileExists(atPath: wwwAppLoadEvents.path) {
                    do {
                        try fileManager.removeItem(at: wwwAppLoadEvents)
                        print("🗑️  Deleted www/OutSystemsUI.Private.ApplicationLoadEvents.mvc.js")
                        deletedCount += 1
                    } catch {
                        print("⚠️ Failed to delete www/ApplicationLoadEvents: \(error.localizedDescription)")
                    }
                }

                print("✅ Total deleted: \(deletedCount) file(s) from cache + www")
            }
        } catch {
            print("⚠️ Could not clean patched files from cache: \(error.localizedDescription)")
        }
    }

    private func reapplyPluginPatches(version: String) async throws {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        print("🔧 Re-applying plugin patches to downloaded files...")

        // Get the cache directory where files were downloaded
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OTAError.downloadFailed("Could not access Application Support directory")
        }

        let cacheKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        let cacheDir = appSupportDir
            .appendingPathComponent("OSNativeCache")
            .appendingPathComponent(cacheKey)

        print("📂 Cache directory: \(cacheDir.path)")

        // Define the patches to apply
        let patchesToApply: [(file: String, searchFor: String, replaceWith: String)] = [
            (
                file: "OutSystemsManifestLoader.js",
                searchFor: "var OSManifestLoader=function(e){",
                replaceWith: """
                // [OSManualOTA Plugin Patch] Offline moduleinfo fallback - MUST BE FIRST!
                (function() {
                    var originalFetch = window.fetch;
                    window.fetch = function(url, options) {
                        return originalFetch.apply(this, arguments).catch(function(error) {
                            // If fetch fails and it's for moduleversioninfo, try loading from cache
                            if (url && url.indexOf('moduleversioninfo') > -1) {
                                console.log('[OSManualOTA] 🔄 moduleversioninfo failed, checking localStorage...');
                                var cachedVersion = localStorage.getItem('os_manual_ota_current_version');
                                if (cachedVersion) {
                                    console.log('[OSManualOTA] ✅ Found cached version, loading moduleinfo: ' + cachedVersion);
                                    // Redirect to cached moduleinfo
                                    var baseUrl = url.substring(0, url.indexOf('moduleversioninfo'));
                                    return originalFetch(baseUrl + 'moduleinfo?' + cachedVersion);
                                }
                            }
                            throw error;
                        });
                    };
                })();
                var OSManifestLoader=function(e){
                """
            ),
            (
                file: "OutSystemsManifestLoader.js",
                searchFor: "function checkForUpdates(",
                replaceWith: """
                // [OSManualOTA Plugin Patch] Check if OTA is blocked
                if (window.localStorage && window.localStorage.getItem('os_manual_ota_blocking_enabled') === 'true') {
                    console.log('[OSManualOTA] 🚫 Blocking automatic manifest fetch');
                    return;
                }

                function checkForUpdates(
                """
            ),
            (
                file: "OutSystemsUI.Private.ApplicationLoadEvents.mvc.js",
                searchFor: "MinimumDisplayTimeMs: 1500",
                replaceWith: """
                MinimumDisplayTimeMs: (window.localStorage && window.localStorage.getItem('os_manual_ota_splash_bypass_enabled') === 'true') ? 50 : 1500
                """
            )
        ]

        var patchedCount = 0
        let allFiles = try fileManager.contentsOfDirectory(atPath: cacheDir.path)
        print("📊 Scanning \(allFiles.count) files in cache...")

        for patch in patchesToApply {
            var foundAndPatched = false

            for fileName in allFiles {
                let filePath = cacheDir.appendingPathComponent(fileName)

                guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                    continue
                }

                // Check if this is the file we're looking for
                if content.contains(patch.file) {
                    print("🔍 Found \(patch.file) as \(fileName)")

                    // Check if already patched
                    if content.contains(patch.replaceWith) {
                        print("   ✓ Already patched, skipping")
                        foundAndPatched = true
                        break
                    }

                    // Check if we can patch it
                    if content.contains(patch.searchFor) {
                        let patchedContent = content.replacingOccurrences(of: patch.searchFor, with: patch.replaceWith)
                        try patchedContent.write(to: filePath, atomically: true, encoding: .utf8)
                        print("   ✅ Patched successfully!")
                        patchedCount += 1
                        foundAndPatched = true
                        break
                    } else {
                        print("   ⚠️  Search string not found, cannot patch")
                    }
                }
            }

            if !foundAndPatched {
                print("⚠️  Could not find or patch: \(patch.file)")
            }
        }

        print("📊 Patching complete: \(patchedCount) file(s) patched")
    }

    // MARK: - Crash Detection
    private func setCrashDetectionFlag() {
        // TODO: Re-enable after testing
        print("🐛 [DEBUG] Crash detection flag DISABLED for testing")
        // defaults.set(true, forKey: OSStorageKey.crashDetection)
    }

    private func clearCrashDetectionFlag() {
        defaults.removeObject(forKey: OSStorageKey.crashDetection)
    }

    private func checkForCrashOnLastUpdate() {
        // TODO: Re-enable after testing
        print("🐛 [DEBUG] Crash detection check DISABLED for testing")

        // Temporarily disabled for testing
        /*
        if defaults.bool(forKey: OSStorageKey.crashDetection) {
            // App crashed after last update, rollback automatically
            print("⚠️ Detected crash after last update, initiating automatic rollback...")
            rollbackToPreviousVersion { success, error in
                if success {
                    print("✅ Automatic rollback successful")
                } else {
                    print("❌ Automatic rollback failed: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
        */
    }

    // MARK: - Network Conditions
    private func checkNetworkConditions() throws {
        // Check if network is available
        // For large updates, check if we're on WiFi
        // This is a simplified version
    }

    // MARK: - Metrics
    private func logUpdateMetrics(
        checkDuration: TimeInterval,
        downloadDuration: TimeInterval,
        downloadSize: Int64,
        filesDownloaded: Int,
        filesSkipped: Int,
        filesFailed: Int,
        success: Bool,
        errorMessage: String?,
        triggerMethod: String
    ) {
        let metrics = OSUpdateMetrics(
            checkDuration: checkDuration,
            downloadDuration: downloadDuration,
            downloadSize: downloadSize,
            filesDownloaded: filesDownloaded,
            filesSkipped: filesSkipped,
            filesFailed: filesFailed,
            success: success,
            errorMessage: errorMessage,
            triggerMethod: triggerMethod,
            timestamp: Date()
        )

        print("📊 OTA Update Metrics: \(metrics.toDictionary())")
        // TODO: Send to analytics platform
    }

    // MARK: - Helper Methods
    private func getBaseURLFromApp() -> String? {
        // Extract from OutSystems app configuration
        // This would typically come from the app's config
        return defaults.string(forKey: "os_manual_ota_base_url")
    }

    private func getHostnameFromApp() -> String? {
        return defaults.string(forKey: "os_manual_ota_hostname")
    }

    private func getApplicationPathFromApp() -> String? {
        return defaults.string(forKey: "os_manual_ota_app_path")
    }

    internal func getOutSystemsCache() -> OSApplicationCache? {
        guard let config = configuration else {
            print("[OSManualOTA] Cannot get cache: configuration not set")
            return nil
        }

        // Get the shared OSNativeCache instance
        guard let cacheInstance = OSNativeCache.sharedInstance() as? OSNativeCache else {
            print("[OSManualOTA] OSNativeCache not available")
            return nil
        }

        // Set current application context
        cacheInstance.setCurrentApplication(config.hostname, application: config.applicationPath)

        // Get the application cache
        let appKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        guard let applicationEntries = cacheInstance.applicationEntries(),
              let appCache = applicationEntries.object(forKey: appKey) as? OSApplicationCache else {
            print("[OSManualOTA] Application cache not found for key: \(appKey)")
            return nil
        }

        return appCache
    }

    // MARK: - Debug/Reset Methods

    /// Resets all stored OTA state (for debugging/testing)
    /// This clears downloaded version, asset hashes, and current version
    func resetOTAState() {
        print("🔄 Resetting OTA state...")
        defaults.removeObject(forKey: OSStorageKey.currentVersion)
        defaults.removeObject(forKey: OSStorageKey.downloadedVersion)
        defaults.removeObject(forKey: OSStorageKey.assetHashes)
        defaults.removeObject(forKey: OSStorageKey.previousVersion)
        defaults.removeObject(forKey: OSStorageKey.lastUpdateCheck)
        defaults.removeObject(forKey: OSStorageKey.pendingSwapVersion)
        defaults.removeObject(forKey: OSStorageKey.pendingSwapTimestamp)
        print("✅ OTA state reset complete")
    }

    // MARK: - Version Token Management

    /// Updates the version token in localStorage so JavaScript can use it
    /// This is read by our patched OutSystemsManifestLoader.js to set the correct version on app start
    /// - Parameter newVersion: The new version token to store
    private func updateVersionInLocalStorage(newVersion: String) {
        // Store in UserDefaults so it persists
        defaults.set(newVersion, forKey: "os_manual_ota_current_version")
        print("✅ Stored version token in UserDefaults: \(newVersion)")

        // Also try to update localStorage through webview if available
        if let webView = getWebView() {
            let jsCode = """
            localStorage.setItem('os_manual_ota_current_version', '\(newVersion)');
            console.log('[OSManualOTA] Native updated localStorage with version: \(newVersion)');
            """
            webView.evaluateJavaScript(jsCode) { result, error in
                if let error = error {
                    print("⚠️  Could not update localStorage: \(error.localizedDescription)")
                } else {
                    print("✅ Updated localStorage with new version token")
                }
            }
        } else {
            print("⚠️  WebView not available - version will be synced on next app start")
        }
    }

    /// Gets the WKWebView instance from the Cordova app
    private func getWebView() -> WKWebView? {
        guard let appDelegate = UIApplication.shared.delegate,
              let window = appDelegate.window as? UIWindow,
              let rootViewController = window.rootViewController else {
            return nil
        }

        // Try to find WKWebView in the view hierarchy
        return findWebView(in: rootViewController.view)
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }

        for subview in view.subviews {
            if let webView = findWebView(in: subview) {
                return webView
            }
        }

        return nil
    }

    /// Patches all cached OutSystemsManifestLoader.js files to add the version override logic
    private func patchCachedManifestLoader() {
        guard let appSupportDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first else {
            print("❌ Could not find Application Support directory")
            return
        }

        let cacheDir = (appSupportDir as NSString).appendingPathComponent("OSNativeCache")
        let fileManager = FileManager.default

        print("📂 Searching for OutSystemsManifestLoader.js in cache...")

        do {
            let cacheDirs = try fileManager.contentsOfDirectory(atPath: cacheDir)
            var patchedCount = 0

            for dir in cacheDirs where dir != "OSCacheManifest.plist" {
                let appCacheDir = (cacheDir as NSString).appendingPathComponent(dir)

                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: appCacheDir, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }

                let files = try fileManager.contentsOfDirectory(atPath: appCacheDir)

                for file in files {
                    let filePath = (appCacheDir as NSString).appendingPathComponent(file)

                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                        continue
                    }

                    // Check if this is OutSystemsManifestLoader.js
                    if content.contains("OSManifestLoader") && content.contains("indexVersionToken") {
                        // Check if already patched by our code
                        if content.contains("OSManualOTA: Intercept indexVersionToken") {
                            print("   ⏭️  Already patched: \(dir)/\(file)")
                            continue
                        }

                        print("🎯 Found unpatched OutSystemsManifestLoader.js at: \(dir)/\(file)")

                        // Add our override code - intercepts the token SETTER
                        let patchCode = """

// 🔧 OSManualOTA: Intercept indexVersionToken setter to use stored value
(function() {
    if (typeof OSManifestLoader !== 'undefined') {
        var originalIndexVersionToken = null;

        // Override the indexVersionToken property with getter/setter
        Object.defineProperty(OSManifestLoader, 'indexVersionToken', {
            get: function() {
                return originalIndexVersionToken;
            },
            set: function(value) {
                // When index.html tries to set the OLD token, replace it with NEW token from storage
                var storedVersion = localStorage.getItem('os_manual_ota_current_version');
                if (storedVersion && storedVersion !== 'unknown' && storedVersion !== value) {
                    console.log('[OSManualOTA] ✅ Intercepted token setter: ' + value + ' -> ' + storedVersion);
                    originalIndexVersionToken = storedVersion;
                } else {
                    originalIndexVersionToken = value;
                    // First time or no override - store what index.html is setting
                    if (value && (!storedVersion || storedVersion === 'unknown')) {
                        localStorage.setItem('os_manual_ota_current_version', value);
                        console.log('[OSManualOTA] Stored initial version: ' + value);
                    }
                }
            },
            configurable: true,
            enumerable: true
        });
    }
})();
"""

                        // Try multiple insertion points
                        var patchedContent: String?

                        // 1. Try after our blocking hook (for www/ version)
                        if let range = content.range(of: "console.log('[OSManualOTA] Blocking hook installed');") {
                            patchedContent = content
                            patchedContent!.insert(contentsOf: patchCode, at: range.upperBound)
                            print("   ✅ Patched after blocking hook (www/ version)")
                        }
                        // 2. Try at end of file (for original OutSystems version from server)
                        else if content.contains("e.indexVersionToken=null") || content.contains("OSManifestLoader") {
                            patchedContent = content + patchCode
                            print("   ✅ Patched at end of file (server version)")
                        }

                        if let finalContent = patchedContent {
                            try finalContent.write(toFile: filePath, atomically: true, encoding: .utf8)
                            patchedCount += 1
                        } else {
                            print("   ⚠️  Could not find insertion point in file")
                        }
                    }
                }
            }

            if patchedCount == 0 {
                print("⚠️  No OutSystemsManifestLoader.js files found to patch")
            } else {
                print("✅ Successfully patched \(patchedCount) OutSystemsManifestLoader.js file(s)")
            }

        } catch {
            print("❌ Error while patching OutSystemsManifestLoader.js: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let otaBlockingStatusChanged = Notification.Name("OSManualOTA.blockingStatusChanged")
    static let splashBypassStatusChanged = Notification.Name("OSManualOTA.splashBypassStatusChanged")
    static let otaUpdateAvailable = Notification.Name("OSManualOTA.updateAvailable")
    static let otaDownloadProgress = Notification.Name("OSManualOTA.downloadProgress")
    static let otaDownloadComplete = Notification.Name("OSManualOTA.downloadComplete")
}
