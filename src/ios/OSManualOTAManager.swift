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
    }

    // MARK: - Configuration
    @objc public func configure(baseURL: String, hostname: String, applicationPath: String) {
        self.configuration = OSUpdateConfiguration(
            baseURL: baseURL,
            hostname: hostname,
            applicationPath: applicationPath
        )
        saveConfiguration()
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

        currentStatus = .checking

        Task {
            do {
                let latestVersion = try await getLatestVersion()
                let currentVersion = getCurrentVersion()

                // Update last check timestamp
                defaults.set(Date(), forKey: OSStorageKey.lastUpdateCheck)

                if latestVersion != currentVersion {
                    currentStatus = .available(version: latestVersion)
                    completion(true, latestVersion, nil)
                } else {
                    currentStatus = .notAvailable
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
                    // 6. Save new version and hashes
                    saveDownloadedVersion(latestVersion)
                    saveAssetHashes(manifest.urlVersions)

                    // 7. Log metrics
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

    private func downloadChangedFiles(
        changedFiles: [String: String],
        manifest: OSModuleManifest,
        version: String
    ) async throws -> Bool {
        guard let config = configuration else {
            throw OTAError.invalidConfiguration
        }

        // Report initial progress
        let totalFiles = manifest.urlVersions.count
        let changedCount = changedFiles.count
        let skippedFiles = totalFiles - changedCount
        progressHandler?(0, changedCount, skippedFiles)

        // Prepare resource list in OutSystems format
        // Format: ["path?hash", "path2?hash2", ...]
        var resourceList = NSMutableArray()
        for (path, hash) in manifest.urlVersions {
            let resourcePath = "\(path)?\(hash)"
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
            let downloadFinishBlock: DownloadFinishBlock = { success in
                if self.downloadCancelled {
                    continuation.resume(returning: false)
                } else if errorOccurred || !success {
                    continuation.resume(throwing: OTAError.downloadFailed("Download failed"))
                } else {
                    continuation.resume(returning: true)
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

    private func saveCurrentVersion(_ version: String) {
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

    // MARK: - Crash Detection
    private func setCrashDetectionFlag() {
        defaults.set(true, forKey: OSStorageKey.crashDetection)
    }

    private func clearCrashDetectionFlag() {
        defaults.removeObject(forKey: OSStorageKey.crashDetection)
    }

    private func checkForCrashOnLastUpdate() {
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
        // Get reference to OutSystems cache if available
        // This would require accessing the OutSystems plugin
        return nil
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
