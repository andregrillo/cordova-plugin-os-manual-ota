//
//  OSUpdateModels.swift
//  OutSystems Manual OTA Plugin
//
//  Data models for OTA updates
//

import Foundation

// MARK: - Update Status
enum OSUpdateStatus {
    case checking
    case available(version: String)
    case notAvailable
    case downloading(progress: OSDownloadProgress)
    case downloaded
    case applying
    case applied
    case failed(error: Error)
}

// MARK: - Download Progress
struct OSDownloadProgress {
    let downloadedFiles: Int
    let totalFiles: Int
    let skippedFiles: Int

    var percentage: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(downloadedFiles) / Double(totalFiles) * 100
    }
}

// MARK: - Version Info
struct OSVersionInfo: Codable {
    let versionToken: String
    let timestamp: Date
    let isPreBundle: Bool

    init(versionToken: String, timestamp: Date = Date(), isPreBundle: Bool = false) {
        self.versionToken = versionToken
        self.timestamp = timestamp
        self.isPreBundle = isPreBundle
    }
}

// MARK: - Module Manifest
struct OSModuleManifest: Codable {
    let versionToken: String
    let urlVersions: [String: String] // path: hash
    let urlMappings: [String: String]?
    let urlMappingsNoCache: [String: String]?

    enum CodingKeys: String, CodingKey {
        case versionToken
        case urlVersions
        case urlMappings
        case urlMappingsNoCache
    }
}

// MARK: - Update Configuration
struct OSUpdateConfiguration {
    let baseURL: String
    let hostname: String
    let applicationPath: String
    let maxParallelDownloads: Int
    let downloadTimeout: TimeInterval
    let wifiOnlyForLargeUpdates: Bool
    let largeSizeThreshold: Int64 // in bytes

    init(
        baseURL: String,
        hostname: String,
        applicationPath: String,
        maxParallelDownloads: Int = 6,
        downloadTimeout: TimeInterval = 60,
        wifiOnlyForLargeUpdates: Bool = true,
        largeSizeThreshold: Int64 = 10_000_000 // 10MB
    ) {
        self.baseURL = baseURL
        self.hostname = hostname
        self.applicationPath = applicationPath
        self.maxParallelDownloads = maxParallelDownloads
        self.downloadTimeout = downloadTimeout
        self.wifiOnlyForLargeUpdates = wifiOnlyForLargeUpdates
        self.largeSizeThreshold = largeSizeThreshold
    }
}

// MARK: - OTA Error Types
enum OTAError: LocalizedError {
    case networkUnavailable
    case versionCheckFailed(String)
    case manifestFetchFailed(String)
    case downloadFailed(String)
    case applyFailed(String)
    case rollbackFailed(String)
    case invalidConfiguration
    case noUpdateAvailable
    case alreadyDownloading
    case cancelled
    case wifiRequired

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection is not available"
        case .versionCheckFailed(let details):
            return "Failed to check for updates: \(details)"
        case .manifestFetchFailed(let details):
            return "Failed to fetch update manifest: \(details)"
        case .downloadFailed(let details):
            return "Download failed: \(details)"
        case .applyFailed(let details):
            return "Failed to apply update: \(details)"
        case .rollbackFailed(let details):
            return "Failed to rollback: \(details)"
        case .invalidConfiguration:
            return "Invalid OTA configuration"
        case .noUpdateAvailable:
            return "No update available"
        case .alreadyDownloading:
            return "Update download already in progress"
        case .cancelled:
            return "Update was cancelled"
        case .wifiRequired:
            return "WiFi connection required for this update"
        }
    }
}

// MARK: - Storage Keys
enum OSStorageKey {
    static let currentVersion = "os_manual_ota_current_version"
    static let previousVersion = "os_manual_ota_previous_version"
    static let downloadedVersion = "os_manual_ota_downloaded_version"
    static let assetHashes = "os_manual_ota_asset_hashes"
    static let otaBlockingEnabled = "os_manual_ota_blocking_enabled"
    static let splashBypassEnabled = "os_manual_ota_splash_bypass_enabled"
    static let lastUpdateCheck = "os_manual_ota_last_check"
    static let crashDetection = "os_manual_ota_crash_detection"
    static let pendingSwapVersion = "os_manual_ota_pending_swap_version"
    static let pendingSwapTimestamp = "os_manual_ota_pending_swap_timestamp"
}

// MARK: - Update Metrics
struct OSUpdateMetrics {
    let checkDuration: TimeInterval
    let downloadDuration: TimeInterval
    let downloadSize: Int64
    let filesDownloaded: Int
    let filesSkipped: Int
    let filesFailed: Int
    let success: Bool
    let errorMessage: String?
    let triggerMethod: String // "background_fetch", "silent_push", "manual"
    let timestamp: Date

    func toDictionary() -> [String: Any] {
        return [
            "checkDuration": checkDuration,
            "downloadDuration": downloadDuration,
            "downloadSize": downloadSize,
            "filesDownloaded": filesDownloaded,
            "filesSkipped": filesSkipped,
            "filesFailed": filesFailed,
            "success": success,
            "errorMessage": errorMessage ?? "",
            "triggerMethod": triggerMethod,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }
}
