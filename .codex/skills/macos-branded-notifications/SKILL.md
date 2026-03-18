---
name: macos-branded-notifications
description: Send branded macOS notifications with custom app icon using terminal-notifier. Use when implementing native Notification Center integration with custom branding.
---

# macOS Branded Notifications

Send native macOS notifications that display your app's custom icon instead of a generic Terminal icon.

## Architecture

```
YourApp.app/
├── Contents/
│   ├── Info.plist           # App bundle metadata
│   └── Resources/
│       ├── AppIcon.icns     # Your app icon (required)
│       ├── success.png      # Optional content images
│       └── failure.png
```

## Implementation Steps

### 1. Create App Bundle Structure
```bash
mkdir -p YourApp.app/Contents/{MacOS,Resources}
```

### 2. Create Info.plist
Key fields:
- `CFBundleIdentifier`: Unique reverse-domain identifier (used with `-sender` flag)
- `CFBundleIconFile`: Name of .icns file (without extension)
- `LSUIElement`: `true` hides app from Dock (background app)

### 3. Generate App Icon (.icns)
```bash
# From a 512x512 or 1024x1024 PNG source
mkdir -p AppIcon.iconset
sips -z 16 16 icon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32 icon.png --out AppIcon.iconset/icon_16x16@2x.png
# ... all sizes up to 512x512@2x
iconutil -c icns AppIcon.iconset -o YourApp.app/Contents/Resources/AppIcon.icns
rm -rf AppIcon.iconset
```

### 4. Register with Launch Services
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /path/to/YourApp.app
```

### 5. Send Notifications
```bash
brew install terminal-notifier
terminal-notifier \
  -title "Your Title" \
  -message "Your message" \
  -sender com.yourcompany.yourapp \
  -sound default
```

### 6. Enable Notifications (REQUIRED!)
1. Open **System Settings** > **Notifications**
2. Find your app in the list
3. Toggle **Allow notifications** ON

## Troubleshooting

- **Generic icon**: Re-register app with `lsregister -f`, then `killall NotificationCenter`
- **Not appearing**: Enable notifications in System Settings for the app
- **Icon cache**: `sudo rm -rf /Library/Caches/com.apple.iconservices.store && killall Finder`
- **Content images**: Use `file://` URL format with `-contentImage` flag
