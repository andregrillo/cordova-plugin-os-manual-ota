# Git Workflow Guide

## Repository Structure

This repository contains the **cordova-plugin-os-manual-ota** plugin with separate branches for platform implementations.

---

## Branches

### **`main`** - Production Ready iOS Implementation
- ✅ Complete iOS implementation
- ✅ All features working
- ✅ Full documentation
- ✅ Production ready

**Last commit:**
```
8b6c183 Initial commit: iOS Manual OTA Plugin
```

### **`feature/android-implementation`** - Android Development Branch
- 🚧 Android implementation in progress
- 📋 TODO list and roadmap in `ANDROID_TODO.md`
- 🎯 Goal: Match iOS feature parity

**Last commit:**
```
2836c04 Android: Add implementation TODO and roadmap
```

---

## Working with Branches

### **View All Branches**
```bash
git branch -a
```

### **Switch to iOS (main)**
```bash
git checkout main
```

### **Switch to Android Development**
```bash
git checkout feature/android-implementation
```

### **View Commit History**
```bash
git log --oneline --graph --all
```

---

## Development Workflow

### **For iOS (main branch):**

```bash
# Switch to main
git checkout main

# Make changes
# ... edit files ...

# Commit
git add .
git commit -m "iOS: Your change description"

# View history
git log --oneline
```

### **For Android (feature branch):**

```bash
# Switch to Android branch
git checkout feature/android-implementation

# Create Android implementation
# ... create src/android/ files ...

# Commit your work
git add .
git commit -m "Android: Your change description"

# Continue working...
```

### **When Android is Complete:**

```bash
# Make sure Android branch is up to date
git checkout feature/android-implementation
git add .
git commit -m "Android: Final implementation complete"

# Switch to main
git checkout main

# Merge Android implementation
git merge feature/android-implementation

# Delete feature branch (optional)
git branch -d feature/android-implementation
```

---

## Commit Message Convention

Use this format for clear commit messages:

```
Platform: Brief description

Detailed explanation (optional)
- Point 1
- Point 2

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Examples:**

```
iOS: Add AppDelegate swizzling

Automatic integration without manual code changes.
- Method swizzling for background operations
- Handles both existing and missing methods
```

```
Android: Implement WorkManager background updates

Add periodic background update checking using WorkManager.
- Supports Android 8+
- Battery-optimized
- Handles Doze mode
```

```
Docs: Update README with Android setup

Add Android-specific installation and configuration steps.
```

---

## Common Git Commands

### **Status and Changes**
```bash
git status                    # See what's changed
git diff                      # See detailed changes
git log --oneline            # View commit history
git log --graph --all        # Visual history with branches
```

### **Staging and Committing**
```bash
git add .                    # Stage all changes
git add file.txt             # Stage specific file
git commit -m "Message"      # Commit with message
git commit --amend           # Edit last commit
```

### **Branches**
```bash
git branch                   # List local branches
git branch -a                # List all branches
git branch name              # Create branch
git checkout name            # Switch branch
git checkout -b name         # Create and switch
git branch -d name           # Delete branch
```

### **Undoing Changes**
```bash
git restore file.txt         # Discard changes in file
git restore --staged file    # Unstage file
git reset HEAD~1             # Undo last commit (keep changes)
git reset --hard HEAD~1      # Undo last commit (discard changes)
```

---

## File Organization

### **Current Files (iOS Complete):**

```
cordova-plugin-os-manual-ota/
├── .git/                              # Git repository
├── .gitignore                         # Git ignore rules
│
├── Documentation (8 files)
│   ├── README.md                      # Main guide
│   ├── INTEGRATION_GUIDE.md           # Setup instructions
│   ├── OTA_BLOCKING_GUIDE.md          # OTA blocking explained
│   ├── SWIZZLING_GUIDE.md             # Swizzling technical guide
│   ├── IMPLEMENTATION_NOTES.md        # OSCacheResources details
│   ├── PLUGIN_SUMMARY.md              # Technical overview
│   ├── CHANGELOG.md                   # Version history
│   └── GIT_WORKFLOW.md                # This file
│
├── Android Branch Only
│   └── ANDROID_TODO.md                # Android implementation roadmap
│
├── Configuration
│   ├── package.json                   # NPM package
│   └── plugin.xml                     # Cordova plugin config
│
├── iOS Implementation
│   └── src/ios/
│       ├── OSManualOTAPlugin.swift           # Cordova bridge
│       ├── OSManualOTAManager.swift          # Main OTA logic
│       ├── OSBackgroundUpdateManager.swift   # Background updates
│       ├── OSUpdateModels.swift              # Data models
│       ├── OSAppDelegateSwizzler.h           # Swizzler header
│       ├── OSAppDelegateSwizzler.m           # Swizzler implementation
│       └── OSManualOTA-Bridging-Header.h     # ObjC bridge
│
├── JavaScript API
│   └── www/
│       └── OSManualOTA.js             # JavaScript interface
│
└── Hooks
    └── hooks/
        └── after_prepare_patch_ota.js # OTA blocking hook
```

### **Future Files (Android - To Be Created):**

```
src/android/
├── OSManualOTAPlugin.kt               # Cordova bridge
├── OSManualOTAManager.kt              # Main OTA logic
├── OSBackgroundUpdateManager.kt       # Background updates
├── OSUpdateModels.kt                  # Data classes
├── workers/
│   └── OTAUpdateWorker.kt            # WorkManager worker
├── receivers/
│   └── FCMReceiver.kt                # FCM receiver
└── services/
    └── OTAUpdateService.kt           # Foreground service
```

---

## Release Workflow (Future)

When ready for release:

### **Version 1.0.0 - iOS Only**

```bash
# Ensure on main branch
git checkout main

# Tag the release
git tag -a v1.0.0-ios -m "Release 1.0.0 - iOS implementation complete"

# Push tag (if remote configured)
git push origin v1.0.0-ios
```

### **Version 1.1.0 - iOS + Android**

```bash
# Merge Android implementation
git checkout main
git merge feature/android-implementation

# Tag the release
git tag -a v1.1.0 -m "Release 1.1.0 - iOS and Android complete"

# Push tag (if remote configured)
git push origin v1.1.0
```

---

## Best Practices

### **✅ DO:**
- Commit often with clear messages
- Use feature branches for major changes
- Test before committing
- Keep commits focused (one change per commit)
- Write descriptive commit messages

### **❌ DON'T:**
- Commit broken code to main
- Mix iOS and Android changes in same commit
- Commit large files or build artifacts
- Force push to main
- Delete branches with unmerged work

---

## Quick Reference

| Task | Command |
|------|---------|
| See what changed | `git status` |
| Switch to iOS | `git checkout main` |
| Switch to Android | `git checkout feature/android-implementation` |
| Commit changes | `git add . && git commit -m "Message"` |
| View history | `git log --oneline` |
| Undo last commit | `git reset HEAD~1` |

---

## Getting Help

- **Git basics:** `git help <command>`
- **This repo status:** `git status`
- **Branch overview:** `git branch -v`
- **Commit history:** `git log --graph --all --oneline`

---

## Summary

**Current state:**
- ✅ Git repository initialized
- ✅ iOS implementation committed to `main`
- ✅ Android branch created: `feature/android-implementation`
- ✅ Android TODO documented

**Next steps:**
1. Work on Android implementation in `feature/android-implementation` branch
2. Commit Android progress regularly
3. When complete, merge to `main`
4. Tag release version

---

**Happy coding! 🚀**
