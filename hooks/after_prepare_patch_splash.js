#!/usr/bin/env node

/**
 * After Prepare Hook - Patch Splash Screen
 *
 * This hook patches the OutSystems ApplicationLoadEvents component to bypass
 * the WebView splash screen when enabled, significantly improving app startup time.
 *
 * When splash bypass is enabled:
 * - Skips the 1.5 second minimum display time
 * - Immediately triggers onLoadComplete callback
 * - Allows app to start much faster
 *
 * The bypass can be enabled/disabled at runtime via the plugin API.
 */

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    console.log('🎨 [OSManualOTA] Patching splash screen...');

    // Only run for iOS platform
    const platforms = context.opts.platforms || context.opts.cordova.platforms;
    if (!platforms || !platforms.includes('ios')) {
        console.log('   Skipping - iOS platform not present');
        return;
    }

    const projectRoot = context.opts.projectRoot;
    const wwwPath = path.join(projectRoot, 'platforms', 'ios', 'www', 'scripts');

    if (!fs.existsSync(wwwPath)) {
        console.log('   www/scripts not found, will run after iOS platform is added');
        return;
    }

    // Patch ApplicationLoadEvents
    patchApplicationLoadEvents(wwwPath);
};

function patchApplicationLoadEvents(wwwPath) {
    const appLoadEventsPath = path.join(wwwPath, 'OutSystemsUI.Private.ApplicationLoadEvents.mvc.js');

    if (!fs.existsSync(appLoadEventsPath)) {
        console.log('   ⚠️  ApplicationLoadEvents.mvc.js not found, splash bypass not applied');
        return;
    }

    let content = fs.readFileSync(appLoadEventsPath, 'utf8');

    // Check if already patched
    if (content.includes('OSManualOTA_SplashBypassHook')) {
        console.log('   ✅ ApplicationLoadEvents already patched for splash bypass');
        return;
    }

    // Find the RegisterListenersJS function and patch it
    const registerListenersPattern = /define\("OutSystemsUI\.Private\.ApplicationLoadEvents\.mvc\$controller\.OnInitialize\.RegisterListenersJS"[^]*?return function \(\$parameters, \$actions, \$roles, \$public\) \{/;

    if (!registerListenersPattern.test(content)) {
        console.log('   ⚠️  Could not find RegisterListenersJS function pattern');
        return;
    }

    // Patch: Add splash bypass check at the beginning of RegisterListenersJS
    const splashBypassPatch = `define("OutSystemsUI.Private.ApplicationLoadEvents.mvc$controller.OnInitialize.RegisterListenersJS", [], function () {
return function ($parameters, $actions, $roles, $public) {
    // OSManualOTA Plugin - Splash Bypass Hook
    window.OSManualOTA_SplashBypassHook = true;

    // Check if splash bypass is enabled
    var splashBypassEnabled = localStorage.getItem('os_manual_ota_splash_bypass_enabled') === 'true';

    if (splashBypassEnabled) {
        console.log('[OSManualOTA] Splash bypass enabled - triggering immediate load');

        // Trigger onLoadComplete immediately with minimal delay
        // We use a small timeout to ensure the DOM is ready
        setTimeout(function() {
            $actions.TriggerOnLoadComplete(window.location.href);
        }, 50); // 50ms minimal delay instead of 1500ms

        // Don't set up the normal upgrade listeners
        return;
    }

    // Original code follows below (when bypass is disabled)
    var start = new Date();`;

    // Replace the RegisterListenersJS function definition
    content = content.replace(
        /define\("OutSystemsUI\.Private\.ApplicationLoadEvents\.mvc\$controller\.OnInitialize\.RegisterListenersJS", \[\], function \(\) \{\s*return function \(\$parameters, \$actions, \$roles, \$public\) \{\s*var start = new Date\(\);/,
        splashBypassPatch
    );

    // Verify patch was applied
    if (!content.includes('OSManualOTA_SplashBypassHook')) {
        console.log('   ❌ Failed to apply splash bypass patch');
        return;
    }

    // Write patched content back
    fs.writeFileSync(appLoadEventsPath, content, 'utf8');
    console.log('   ✅ ApplicationLoadEvents patched for splash bypass');
    console.log('      - Splash bypass can be controlled via localStorage');
    console.log('      - When enabled: ~50ms delay instead of 1500ms minimum');
}
