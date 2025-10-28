#!/usr/bin/env node

/**
 * After Prepare Hook - Setup Bridging Header
 *
 * This hook runs after 'cordova prepare' and ensures the necessary
 * Swift header import is added to the app's existing Bridging-Header.h file.
 *
 * Running on 'after_prepare' ensures our import persists even if other
 * processes modify the bridging header during the build process.
 *
 * OutSystems apps already have a Bridging-Header.h configured at:
 * platforms/ios/{AppName}/Bridging-Header.h
 *
 * We simply append our Swift interface import to that file.
 */

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    console.log('🔧 [OSManualOTA] Setting up bridging header...');

    // Only run for iOS platform
    if (!context.opts.platforms.includes('ios') &&
        !context.opts.cordova.platforms.includes('ios')) {
        console.log('   Skipping - iOS platform not present');
        return;
    }

    const projectRoot = context.opts.projectRoot;
    const iosPlatformPath = path.join(projectRoot, 'platforms', 'ios');

    // Check if iOS platform exists
    if (!fs.existsSync(iosPlatformPath)) {
        console.log('   iOS platform not found yet, will run after platform add');
        return;
    }

    // Find the app folder (it's named after the app)
    const items = fs.readdirSync(iosPlatformPath);
    let appFolderName = null;

    for (const item of items) {
        const itemPath = path.join(iosPlatformPath, item);
        const stat = fs.statSync(itemPath);

        // Look for folders that aren't common Cordova folders
        if (stat.isDirectory() &&
            item !== 'CordovaLib' &&
            item !== 'www' &&
            item !== 'platform_www' &&
            !item.endsWith('.xcodeproj') &&
            !item.endsWith('.xcworkspace')) {

            // Check if this folder has a Bridging-Header.h
            const bridgingHeaderPath = path.join(itemPath, 'Bridging-Header.h');
            if (fs.existsSync(bridgingHeaderPath)) {
                appFolderName = item;
                break;
            }
        }
    }

    if (!appFolderName) {
        console.log('⚠️  [OSManualOTA] Could not find app folder with Bridging-Header.h');
        console.log('   This is normal if the plugin is installed before the iOS platform.');
        console.log('   The bridging header will be configured when you run "cordova prepare ios"');
        return;
    }

    const bridgingHeaderPath = path.join(iosPlatformPath, appFolderName, 'Bridging-Header.h');

    console.log(`   Found app folder: ${appFolderName}`);
    console.log(`   Bridging header: ${bridgingHeaderPath}`);

    // Read existing bridging header
    let bridgingHeaderContent = fs.readFileSync(bridgingHeaderPath, 'utf8');

    // The bridging header exists and is configured by Cordova/OutSystems
    // We don't need to modify it - the Swift-to-Objective-C header is auto-generated
    // by Xcode as "ProductModuleName-Swift.h"
    console.log('✅ [OSManualOTA] Bridging header found (no modification needed)');
    console.log('   Swift classes will be accessible via auto-generated header');
};
