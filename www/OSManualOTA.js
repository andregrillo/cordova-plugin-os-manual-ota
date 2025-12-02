/**
 * OSManualOTA.js
 * JavaScript interface for OutSystems Manual OTA Plugin
 */

var exec = require('cordova/exec');
var cordova = require('cordova');

var OSManualOTA = {

    /**
     * Configure the OTA plugin with your OutSystems environment details
     * @param {Object} config - Configuration object
     * @param {string} config.baseURL - Base URL of your OutSystems environment (e.g., "https://yourenv.outsystems.net/YourApp")
     * @param {string} config.hostname - Hostname (e.g., "yourenv.outsystems.net")
     * @param {string} config.applicationPath - Application path (e.g., "/YourApp")
     * @param {Function} successCallback - Called when configuration succeeds
     * @param {Function} errorCallback - Called when configuration fails
     */
    configure: function(config, successCallback, errorCallback) {
        if (!config || !config.baseURL || !config.hostname || !config.applicationPath) {
            errorCallback && errorCallback('Invalid configuration: baseURL, hostname, and applicationPath are required');
            return;
        }

        // Try to get current version from OutSystems
        var currentVersion = null;

        // Try from OSManifestLoader.indexVersionToken (most reliable)
        if (typeof OSManifestLoader !== 'undefined' && OSManifestLoader.indexVersionToken) {
            currentVersion = OSManifestLoader.indexVersionToken;
            console.log('[OSManualOTA] Got current version from indexVersionToken: ' + currentVersion);
        }

        // Pass current version to native if available
        if (currentVersion) {
            config.currentVersion = currentVersion;
        }

        exec(successCallback, errorCallback, 'OSManualOTA', 'configure', [config]);
    },

    /**
     * Check if an update is available
     * @param {Function} successCallback - Called with {hasUpdate: boolean, version: string}
     * @param {Function} errorCallback - Called when check fails
     */
    checkForUpdates: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'checkForUpdates', []);
    },

    /**
     * Download an available update
     * @param {Function} progressCallback - Called with progress updates {downloaded: number, total: number, skipped: number, percentage: number}
     * @param {Function} errorCallback - Called when download fails
     * @param {Function} completeCallback - Called when download completes with {success: boolean}
     */
    downloadUpdate: function(progressCallback, errorCallback, completeCallback) {
        var combinedCallback = function(result) {
            // Check if this is a progress update or final result
            if (result.success !== undefined) {
                // Final result
                completeCallback && completeCallback(result);
            } else if (result.downloaded !== undefined) {
                // Progress update
                progressCallback && progressCallback(result);
            }
        };

        exec(combinedCallback, errorCallback, 'OSManualOTA', 'downloadUpdate', []);
    },

    /**
     * Apply the downloaded update (will take effect on next app restart)
     * @param {Function} successCallback - Called when update is marked to be applied
     * @param {Function} errorCallback - Called when apply fails
     */
    applyUpdate: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'applyUpdate', []);
    },

    /**
     * Rollback to the previous version
     * @param {Function} successCallback - Called when rollback succeeds
     * @param {Function} errorCallback - Called when rollback fails
     */
    rollback: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'rollback', []);
    },

    /**
     * Cancel an ongoing download
     * @param {Function} successCallback - Called when cancellation succeeds
     * @param {Function} errorCallback - Called when cancellation fails
     */
    cancelDownload: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'cancelDownload', []);
    },

    /**
     * Get current version information
     * @param {Function} successCallback - Called with version info object
     * @param {Function} errorCallback - Called when getting info fails
     * Returns: {
     *   currentVersion: string,
     *   downloadedVersion: string,
     *   previousVersion: string,
     *   lastUpdateCheck: number,
     *   isUpdateDownloaded: boolean,
     *   isDownloading: boolean
     * }
     */
    getVersionInfo: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'getVersionInfo', []);
    },

    /**
     * Enable or disable automatic OTA blocking
     * @param {boolean} enabled - True to block automatic OTA, false to allow it
     * @param {Function} successCallback - Called when setting succeeds
     * @param {Function} errorCallback - Called when setting fails
     */
    setOTABlockingEnabled: function(enabled, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'setOTABlockingEnabled', [enabled]);
    },

    /**
     * Check if automatic OTA blocking is enabled
     * @param {Function} successCallback - Called with {enabled: boolean}
     * @param {Function} errorCallback - Called when check fails
     */
    isOTABlockingEnabled: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'isOTABlockingEnabled', []);
    },

    /**
     * Enable or disable background updates
     * @param {boolean} enabled - True to enable background updates, false to disable
     * @param {Function} successCallback - Called when setting succeeds
     * @param {Function} errorCallback - Called when setting fails
     */
    enableBackgroundUpdates: function(enabled, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'enableBackgroundUpdates', [enabled]);
    },

    /**
     * Check if background updates are enabled
     * @param {Function} successCallback - Called with {enabled: boolean}
     * @param {Function} errorCallback - Called when check fails
     */
    isBackgroundFetchEnabled: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'isBackgroundFetchEnabled', []);
    },

    /**
     * Set the minimum background fetch interval
     * @param {number} interval - Interval in seconds (minimum value handled by iOS)
     * @param {Function} successCallback - Called when setting succeeds
     * @param {Function} errorCallback - Called when setting fails
     */
    setBackgroundFetchInterval: function(interval, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'setBackgroundFetchInterval', [interval]);
    },

    /**
     * Reset OTA state (clears cached versions and hashes) - for debugging/testing
     * @param {Function} successCallback - Called when reset succeeds
     * @param {Function} errorCallback - Called when reset fails
     */
    resetOTAState: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'resetOTAState', []);
    },

    /**
     * Convenience method: Check and download update if available
     * @param {Function} progressCallback - Called with progress updates
     * @param {Function} successCallback - Called when process completes with {hasUpdate: boolean, downloaded: boolean}
     * @param {Function} errorCallback - Called when process fails
     */
    checkAndDownload: function(progressCallback, successCallback, errorCallback) {
        var self = this;

        this.checkForUpdates(
            function(checkResult) {
                if (checkResult.hasUpdate) {
                    console.log('[OSManualOTA] Update available: ' + checkResult.version);

                    self.downloadUpdate(
                        progressCallback,
                        errorCallback,
                        function(downloadResult) {
                            successCallback && successCallback({
                                hasUpdate: true,
                                downloaded: downloadResult.success,
                                version: checkResult.version
                            });
                        }
                    );
                } else {
                    console.log('[OSManualOTA] No update available');
                    successCallback && successCallback({
                        hasUpdate: false,
                        downloaded: false
                    });
                }
            },
            errorCallback
        );
    },

    /**
     * Convenience method: Check, download, and apply update if available
     * @param {Function} progressCallback - Called with progress updates
     * @param {Function} successCallback - Called when process completes
     * @param {Function} errorCallback - Called when process fails
     */
    checkDownloadAndApply: function(progressCallback, successCallback, errorCallback) {
        var self = this;

        this.checkAndDownload(
            progressCallback,
            function(result) {
                if (result.hasUpdate && result.downloaded) {
                    console.log('[OSManualOTA] Applying update...');

                    self.applyUpdate(
                        function(applyResult) {
                            successCallback && successCallback({
                                hasUpdate: true,
                                downloaded: true,
                                applied: true,
                                message: applyResult.message
                            });
                        },
                        errorCallback
                    );
                } else {
                    successCallback && successCallback({
                        hasUpdate: result.hasUpdate,
                        downloaded: result.downloaded,
                        applied: false
                    });
                }
            },
            errorCallback
        );
    },

    /**
     * Enable or disable splash screen bypass
     * When enabled, the WebView splash screen is skipped, improving startup time
     * @param {boolean} enabled - True to bypass splash screen, false to show it normally
     * @param {Function} successCallback - Called when setting succeeds
     * @param {Function} errorCallback - Called when setting fails
     */
    setSplashBypassEnabled: function(enabled, successCallback, errorCallback) {
        // Set in native plugin
        exec(
            function() {
                console.log('[OSManualOTA] Splash bypass ' + (enabled ? 'enabled' : 'disabled'));
                successCallback && successCallback();
            },
            errorCallback,
            'OSManualOTA',
            'setSplashBypassEnabled',
            [enabled]
        );
    },

    /**
     * Check if splash screen bypass is enabled
     * @param {Function} successCallback - Called with {enabled: boolean}
     * @param {Function} errorCallback - Called when check fails
     */
    isSplashBypassEnabled: function(successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'OSManualOTA', 'isSplashBypassEnabled', []);
    },

    /**
     * Event listener for OTA blocking status changes
     * @param {Function} callback - Called when blocking status changes with {enabled: boolean}
     */
    onBlockingStatusChanged: function(callback) {
        document.addEventListener('OSManualOTA.blockingStatusChanged', function(event) {
            callback && callback(event);
        }, false);
    }
};

module.exports = OSManualOTA;
