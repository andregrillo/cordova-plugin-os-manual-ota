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
    private let backgroundManager = OSBackgroundUpdateManager.shared

    // Store callback IDs for progress updates
    private var downloadCallbackId: String?

    // MARK: - Plugin Lifecycle
    override func pluginInitialize() {
        super.pluginInitialize()
        print("🚀 OSManualOTA Plugin initialized")

        // Configure OTA manager with app settings
        configureFromSettings()

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

        otaManager.configure(baseURL: baseURL, hostname: hostname, applicationPath: applicationPath)

        let result = CDVPluginResult(status: .ok, messageAs: "Configuration saved")
        commandDelegate.send(result, callbackId: command.callbackId)
    }

    // MARK: - Check for Updates
    @objc(checkForUpdates:)
    func checkForUpdates(_ command: CDVInvokedUrlCommand) {
        commandDelegate.run {
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
}
