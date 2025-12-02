//
//  OSManualOTAManager.swift
//  OutSystems Manual OTA Plugin
//
//  Main manager class for manual OTA updates
//

import Foundation
import UIKit

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

        // Register for app foreground notifications to check for pending swaps
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
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
        self.configuration = OSUpdateConfiguration(
            baseURL: baseURL,
            hostname: hostname,
            applicationPath: applicationPath
        )
        saveConfiguration()

        // If JavaScript provided current version, use it directly
        if let version = currentVersion, !version.isEmpty {
            print("[OSManualOTA] Setting current version from JavaScript: \(version)")
            saveCurrentVersion(version)
        } else {
            // Otherwise try to initialize from OutSystems cache
            initializeCurrentVersionIfNeeded()
        }
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
                let latestVersion = try await getLatestVersion()
                var currentVersion = getCurrentVersion()

                print("[OSManualOTA] 🔍 Version comparison:")
                print("[OSManualOTA]    Current: '\(currentVersion)'")
                print("[OSManualOTA]    Latest:  '\(latestVersion)'")
                print("[OSManualOTA]    Match: \(latestVersion == currentVersion)")

                // If still unknown, use the latest version as current (first time)
                if currentVersion == "unknown" {
                    print("[OSManualOTA] First time check - setting current version to: \(latestVersion)")
                    saveCurrentVersion(latestVersion)
                    currentVersion = latestVersion
                }

                // Update last check timestamp
                defaults.set(Date(), forKey: OSStorageKey.lastUpdateCheck)

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

        // Prepare resource list in OutSystems format
        // Format: ["path?hash", "path2?hash2", ...]
        var resourceList = NSMutableArray()
        for (path, hash) in manifest.urlVersions {
            // Check if hash already starts with '?' to avoid double question marks
            let resourcePath: String
            if hash.hasPrefix("?") {
                resourcePath = "\(path)\(hash)"
            } else {
                resourcePath = "\(path)?\(hash)"
            }
            resourceList.add(resourcePath)
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

                        // Mark that an update is ready to be applied
                        // Don't swap cache here if we're in background - file writes will fail!
                        self.defaults.set(version, forKey: OSStorageKey.pendingSwapVersion)
                        self.defaults.set(Date().timeIntervalSince1970, forKey: OSStorageKey.pendingSwapTimestamp)
                        print("✅ Update downloaded and registered - marked for swap on foreground")

                        continuation.resume(returning: true)
                    } catch {
                        print("❌ Failed to register cache frame: \(error.localizedDescription)")
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
    private func getCurrentVersion() -> String {
        return defaults.string(forKey: OSStorageKey.currentVersion) ?? "unknown"
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

        // CRITICAL: Write the manifest to disk to persist the swap
        cacheInstance.writeManifest()
        print("✅ Cache manifest written to disk")

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

    /*
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

        // Find the NEW hashes (server's expected hashes) for these files in the manifest
        var newHashesToDelete: [String] = []
        for (path, hash) in manifest.urlVersions {
            for patchedPath in patchedFilePaths {
                if path.contains(patchedPath) {
                    // Extract just the hash part (remove the '?' prefix if present)
                    let cleanHash = hash.hasPrefix("?") ? String(hash.dropFirst()) : hash
                    newHashesToDelete.append(cleanHash)
                    print("🎯 Will delete NEW hash for: \(path) (hash: \(cleanHash))")
                }
            }
        }

        // Also get OLD hashes from saved asset hashes (previous version's hashes)
        var oldHashesToDelete: [String] = []
        if let savedHashesData = defaults.data(forKey: OSStorageKey.assetHashes),
           let oldHashes = try? JSONDecoder().decode([String: String].self, from: savedHashesData) {
            for (path, hash) in oldHashes {
                for patchedPath in patchedFilePaths {
                    if path.contains(patchedPath) {
                        let cleanHash = hash.hasPrefix("?") ? String(hash.dropFirst()) : hash
                        oldHashesToDelete.append(cleanHash)
                        print("🎯 Will delete OLD hash for: \(path) (hash: \(cleanHash))")
                    }
                }
            }
        }

        let allHashesToDelete = newHashesToDelete + oldHashesToDelete

        guard !allHashesToDelete.isEmpty else {
            print("⚠️ No patched files found in manifest")
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: cacheDir.path)
            print("📁 Found \(files.count) files in cache directory")
            var deletedCount = 0

            // Also look for files by checking their content (since cache names might not match manifest hashes)
            // This happens when files were previously cached with old hashes
            var jsFilesChecked = 0
            for fileName in files {
                let filePath = cacheDir.appendingPathComponent(fileName)

                // First, try exact hash match (check both old and new hashes)
                var shouldDelete = false
                var deleteReason = ""
                for hash in allHashesToDelete {
                    if fileName == hash || fileName.contains(hash) {
                        shouldDelete = true
                        deleteReason = "hash match"
                        print("🎯 Matched by hash: \(fileName)")
                        break
                    }
                }

                // If no hash match, check file content for identifying strings
                if !shouldDelete, let content = try? String(contentsOf: filePath, encoding: .utf8) {
                    jsFilesChecked += 1

                    // Check if this is OutSystemsManifestLoader.js
                    if content.contains("OutSystemsManifestLoader") && content.contains("checkForUpdates") {
                        shouldDelete = true
                        deleteReason = "ManifestLoader content"
                        print("🎯 Matched by content: OutSystemsManifestLoader.js in file \(fileName)")

                        // Show first 200 chars to verify it's the right file
                        let preview = String(content.prefix(200))
                        print("   Preview: \(preview)...")
                    }
                    // Check if this is ApplicationLoadEvents
                    else if content.contains("ApplicationLoadEvents") && content.contains("MinimumDisplayTimeMs") {
                        shouldDelete = true
                        deleteReason = "ApplicationLoadEvents content"
                        print("🎯 Matched by content: ApplicationLoadEvents in file \(fileName)")
                    }
                }

                if shouldDelete {
                    do {
                        try fileManager.removeItem(at: filePath)
                        print("🗑️  Deleted cached file: \(fileName) (reason: \(deleteReason))")
                        deletedCount += 1
                    } catch {
                        print("⚠️ Failed to delete \(fileName): \(error.localizedDescription)")
                    }
                }
            }

            print("✅ Deleted \(deletedCount) cached file(s), checked \(jsFilesChecked) JS files (target: old+new hashes)")

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

        print("🔧 Re-applying plugin patches after OTA download...")

        // Get the cache directory where files were downloaded
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OTAError.downloadFailed("Could not access Application Support directory")
        }

        let cacheKey = OSCacheHelper.cacheKey(forHostname: config.hostname, andApplication: config.applicationPath)
        let cacheDir = appSupportDir
            .appendingPathComponent("OSNativeCache")
            .appendingPathComponent(cacheKey)

        // Files to patch with their modifications
        let patchesToApply: [(file: String, searchFor: String, replaceWith: String)] = [
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
        for patch in patchesToApply {
            // Find the file in cache (it's stored as a hash)
            let files = try fileManager.contentsOfDirectory(atPath: cacheDir.path)

            for fileName in files {
                let filePath = cacheDir.appendingPathComponent(fileName)

                guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                    continue
                }

                // Check if this is the file we're looking for
                if content.contains(patch.file) || fileName.contains(patch.file) {
                    // Apply the patch
                    if content.contains(patch.searchFor) && !content.contains(patch.replaceWith) {
                        let patchedContent = content.replacingOccurrences(of: patch.searchFor, with: patch.replaceWith)
                        try patchedContent.write(to: filePath, atomically: true, encoding: .utf8)
                        print("✅ Re-patched: \(patch.file)")
                        patchedCount += 1
                    }
                }
            }
        }

        if patchedCount > 0 {
            print("✅ Successfully re-applied \(patchedCount) plugin patch(es)")
        } else {
            print("⚠️ No patches applied - files may already be patched or not found")
        }
    }
    */

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

    private func getOutSystemsCache() -> OSApplicationCache? {
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
}

// MARK: - Notification Names
extension Notification.Name {
    static let otaBlockingStatusChanged = Notification.Name("OSManualOTA.blockingStatusChanged")
    static let splashBypassStatusChanged = Notification.Name("OSManualOTA.splashBypassStatusChanged")
    static let otaUpdateAvailable = Notification.Name("OSManualOTA.updateAvailable")
    static let otaDownloadProgress = Notification.Name("OSManualOTA.downloadProgress")
    static let otaDownloadComplete = Notification.Name("OSManualOTA.downloadComplete")
}
