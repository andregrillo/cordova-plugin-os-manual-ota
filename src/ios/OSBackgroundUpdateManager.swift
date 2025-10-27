//
//  OSBackgroundUpdateManager.swift
//  OutSystems Manual OTA Plugin
//
//  Handles Background Fetch and Silent Push Notifications for automatic updates
//

import Foundation
import UIKit
import BackgroundTasks

@objc public class OSBackgroundUpdateManager: NSObject {

    // MARK: - Singleton
    @objc public static let shared = OSBackgroundUpdateManager()

    // MARK: - Properties
    private let otaManager = OSManualOTAManager.shared
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // Background task identifier
    private let backgroundTaskIdentifier = "com.outsystems.manual-ota.refresh"

    // MARK: - Initialization
    private override init() {
        super.init()
        registerBackgroundTasks()
    }

    // MARK: - Background Fetch (iOS 7+)
    @objc public func performBackgroundFetch(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        print("🔄 Background Fetch triggered - checking for OTA updates...")

        // Start background task to ensure we have time to complete
        startBackgroundTask()

        otaManager.checkForUpdates { [weak self] hasUpdate, version, error in
            guard let self = self else {
                completion(.failed)
                return
            }

            if let error = error {
                print("❌ Background fetch check failed: \(error.localizedDescription)")
                self.endBackgroundTask()
                completion(.failed)
                return
            }

            if hasUpdate {
                print("✅ Update available: \(version ?? "unknown")")

                // Download the update in background
                self.downloadUpdateInBackground { success in
                    self.endBackgroundTask()
                    if success {
                        print("✅ Background update download completed")
                        completion(.newData)

                        // Notify user (optional)
                        self.showUpdateAvailableNotification(version: version)
                    } else {
                        print("❌ Background update download failed")
                        completion(.failed)
                    }
                }
            } else {
                print("ℹ️ No update available")
                self.endBackgroundTask()
                completion(.noData)
            }
        }
    }

    // MARK: - BGAppRefreshTask (iOS 13+)
    private func registerBackgroundTasks() {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: backgroundTaskIdentifier,
                using: nil
            ) { [weak self] task in
                self?.handleAppRefreshTask(task: task as! BGAppRefreshTask)
            }
        }
    }

    @available(iOS 13.0, *)
    private func handleAppRefreshTask(task: BGAppRefreshTask) {
        print("🔄 BGAppRefreshTask triggered - checking for OTA updates...")

        // Schedule next refresh
        scheduleAppRefreshTask()

        // Create operation for the task
        let operation = BlockOperation {
            self.performBackgroundUpdateCheck { result in
                task.setTaskCompleted(success: result == .newData)
            }
        }

        // Handle task expiration
        task.expirationHandler = {
            operation.cancel()
            print("⚠️ BGAppRefreshTask expired")
        }

        // Start operation
        operation.start()
    }

    @available(iOS 13.0, *)
    @objc public func scheduleAppRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Scheduled next BGAppRefreshTask")
        } catch {
            print("❌ Failed to schedule BGAppRefreshTask: \(error)")
        }
    }

    // MARK: - Silent Push Notification Handler
    @objc public func handleSilentPushNotification(
        userInfo: [AnyHashable: Any],
        completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("🔔 Silent push notification received")

        // Check if this is an OTA update notification
        guard let otaInfo = userInfo["ota_update"] as? [String: Any] else {
            print("ℹ️ Not an OTA update notification")
            completion(.noData)
            return
        }

        let version = otaInfo["version"] as? String
        let immediate = otaInfo["immediate"] as? Bool ?? false

        print("📦 OTA update push received for version: \(version ?? "unknown"), immediate: \(immediate)")

        // Start background task
        startBackgroundTask()

        // Handle foreground vs background
        if UIApplication.shared.applicationState == .active {
            print("ℹ️ App in foreground - scheduling download for later")
            // Schedule download for next background opportunity
            if #available(iOS 13.0, *) {
                scheduleAppRefreshTask()
            }
            endBackgroundTask()
            completion(.newData)
        } else {
            print("⬇️ App in background - downloading update now")
            // Download immediately in background
            downloadUpdateInBackground { [weak self] success in
                self?.endBackgroundTask()
                completion(success ? .newData : .failed)
            }
        }
    }

    // MARK: - Private Helpers
    private func performBackgroundUpdateCheck(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        otaManager.checkForUpdates { [weak self] hasUpdate, version, error in
            guard let self = self else {
                completion(.failed)
                return
            }

            if error != nil {
                completion(.failed)
                return
            }

            if hasUpdate {
                self.downloadUpdateInBackground { success in
                    completion(success ? .newData : .failed)
                }
            } else {
                completion(.noData)
            }
        }
    }

    private func downloadUpdateInBackground(completion: @escaping (Bool) -> Void) {
        let startTime = Date()

        otaManager.downloadUpdate(
            progressHandler: { downloaded, total, skipped in
                print("⬇️ Progress: \(downloaded)/\(total) files downloaded, \(skipped) skipped")
            },
            errorHandler: { error in
                print("❌ Download error: \(error)")
            },
            completion: { [weak self] success in
                let duration = Date().timeIntervalSince(startTime)
                print("⏱️ Background download completed in \(String(format: "%.2f", duration))s, success: \(success)")

                if success {
                    // Automatically apply the update (will take effect on next launch)
                    self?.otaManager.applyUpdate { applied, error in
                        if applied {
                            print("✅ Update applied successfully - will take effect on next app launch")
                        } else {
                            print("⚠️ Failed to apply update: \(error?.localizedDescription ?? "unknown")")
                        }
                        completion(applied)
                    }
                } else {
                    completion(false)
                }
            }
        )
    }

    // MARK: - Background Task Management
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            print("⚠️ Background task expired")
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - User Notifications
    private func showUpdateAvailableNotification(version: String?) {
        let content = UNMutableNotificationContent()
        content.title = "App Update Available"
        content.body = "A new version has been downloaded and will be applied when you restart the app."
        content.sound = .default

        if let version = version {
            content.userInfo = ["version": version]
        }

        let request = UNNotificationRequest(
            identifier: "os-manual-ota-update-available",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to show notification: \(error)")
            }
        }
    }

    // MARK: - Configuration
    @objc public func setMinimumBackgroundFetchInterval(_ interval: TimeInterval) {
        UIApplication.shared.setMinimumBackgroundFetchInterval(interval)
        print("✅ Set minimum background fetch interval to \(interval)s")
    }

    @objc public func enableBackgroundUpdates(_ enabled: Bool) {
        if enabled {
            setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
            if #available(iOS 13.0, *) {
                scheduleAppRefreshTask()
            }
            print("✅ Background updates enabled")
        } else {
            setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
            if #available(iOS 13.0, *) {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            }
            print("⚠️ Background updates disabled")
        }
    }
}
