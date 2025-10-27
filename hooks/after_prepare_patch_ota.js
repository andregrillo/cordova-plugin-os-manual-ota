#!/usr/bin/env node

/**
 * Hook: Patch OutSystemsManifestLoader.js to enable OTA blocking
 *
 * This hook runs after cordova prepare and patches the OutSystemsManifestLoader.js
 * file to check if OSManualOTA plugin has blocking enabled before allowing
 * automatic OTA updates to proceed.
 */

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    console.log('🔧 OSManualOTA: Patching OutSystemsManifestLoader.js...');

    const platforms = context.opts.platforms || context.opts.cordova.platforms;

    if (!platforms || platforms.length === 0) {
        console.log('⚠️  No platforms found, skipping patch');
        return;
    }

    platforms.forEach(function(platform) {
        if (platform === 'ios' || platform === 'android') {
            patchManifestLoader(context, platform);
        }
    });
};

function patchManifestLoader(context, platform) {
    const platformPath = path.join(context.opts.projectRoot, 'platforms', platform);
    const wwwPath = platform === 'ios' ? path.join(platformPath, 'www') : path.join(platformPath, 'assets', 'www');
    const loaderPath = path.join(wwwPath, 'scripts', 'OutSystemsManifestLoader.js');

    if (!fs.existsSync(loaderPath)) {
        console.log(`⚠️  OutSystemsManifestLoader.js not found at: ${loaderPath}`);
        return;
    }

    console.log(`📝 Patching: ${loaderPath}`);

    let content = fs.readFileSync(loaderPath, 'utf8');

    // Check if already patched
    if (content.indexOf('OSManualOTA_BlockingHook') !== -1) {
        console.log('✅ Already patched, skipping');
        return;
    }

    // Create the patch code
    const patchCode = `
// ============================================================================
// OSManualOTA Plugin - Automatic OTA Blocking Hook
// ============================================================================
// This code intercepts OutSystems automatic OTA updates and checks if
// the OSManualOTA plugin has blocking enabled. If blocking is enabled,
// it prevents the automatic update from running.
// ============================================================================

(function() {
    // Mark as patched
    window.OSManualOTA_BlockingHook = true;

    // Store reference to original OSManifestLoader
    var OriginalOSManifestLoader = window.OSManifestLoader || {};

    // Store original functions
    var originalGetLatestVersion = OriginalOSManifestLoader.getLatestVersion;
    var originalGetLatestManifest = OriginalOSManifestLoader.getLatestManifest;

    console.log('[OSManualOTA] Blocking hook installed');

    // Helper to check if blocking is enabled
    function isBlockingEnabled() {
        // Check if plugin is loaded
        if (!window.OSManualOTA) {
            console.log('[OSManualOTA] Plugin not loaded yet, allowing OTA');
            return false;
        }

        // Check localStorage for blocking state
        var blockingEnabled = localStorage.getItem('os_manual_ota_blocking_enabled');
        return blockingEnabled === 'true';
    }

    // Helper to get current version
    function getCurrentVersion() {
        return localStorage.getItem('os_manual_ota_current_version') || 'unknown';
    }

    // Override getLatestVersion
    if (originalGetLatestVersion && typeof originalGetLatestVersion === 'function') {
        OriginalOSManifestLoader.getLatestVersion = function() {
            if (isBlockingEnabled()) {
                console.log('[OSManualOTA] 🚫 Blocking automatic version check');

                // Return fake version (current version) to prevent update
                var currentVersion = getCurrentVersion();
                return Promise.resolve({
                    versionToken: currentVersion
                });
            }

            console.log('[OSManualOTA] ✅ Allowing automatic version check');
            return originalGetLatestVersion.apply(this, arguments);
        };
    }

    // Override getLatestManifest
    if (originalGetLatestManifest && typeof originalGetLatestManifest === 'function') {
        OriginalOSManifestLoader.getLatestManifest = function() {
            if (isBlockingEnabled()) {
                console.log('[OSManualOTA] 🚫 Blocking automatic manifest fetch');

                // Return fake manifest to prevent update
                return Promise.resolve({
                    manifest: {
                        versionToken: getCurrentVersion(),
                        urlVersions: {}
                    }
                });
            }

            console.log('[OSManualOTA] ✅ Allowing automatic manifest fetch');
            return originalGetLatestManifest.apply(this, arguments);
        };
    }

    // Update window.OSManifestLoader
    window.OSManifestLoader = OriginalOSManifestLoader;

    console.log('[OSManualOTA] ✅ Blocking hook active');
})();

// ============================================================================
// End of OSManualOTA Plugin Hook
// ============================================================================

`;

    // Prepend the patch to the original content
    const patchedContent = patchCode + content;

    // Write patched file
    fs.writeFileSync(loaderPath, patchedContent, 'utf8');

    console.log('✅ OutSystemsManifestLoader.js successfully patched!');
    console.log('   - Automatic OTA updates can now be blocked via plugin');
    console.log('   - Use OSManualOTA.setOTABlockingEnabled(true) to enable blocking');
}
