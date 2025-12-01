# ReFinder

A macOS menu bar application that intercepts clicks on the Finder icon in the Dock and either blocks them or redirects them to launch an alternative file manager.

## Features

- **Block Finder**: Clicking the Finder icon in Dock does nothing
- **Redirect to Alternative App**: Opens your preferred file manager (e.g., QSpace Pro, Bloom, Forklift, etc.) instead of Finder
- **Menu bar control**: Easy toggle on/off from the menu bar
- **Persistent settings**: Your configuration is saved between launches

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode 15+ (for building)
- Accessibility permissions must be granted

## How It Works

The app uses:
1. **CGEvent Tap** - Low-level API to intercept mouse events system-wide
2. **Accessibility API (AXUIElement)** - To identify which Dock icon is being clicked
3. **NSWorkspace** - To launch alternative applications

When a left mouse click is detected in the Dock area, the app queries the Accessibility API to determine if the Finder icon is being clicked. If so, it either consumes the event (blocking Finder) or launches your configured alternative app.

## Building

### Option 1: Using Xcode

1. Open `ReFinder.xcodeproj` in Xcode
2. Select your Team in Signing & Capabilities (or disable code signing for local use)
3. Build and Run (⌘R)

### Option 2: Using Command Line

```bash
cd ReFinder
xcodebuild -project ReFinder.xcodeproj -scheme ReFinder -configuration Release build
```

The built app will be in `build/Release/ReFinder.app`

## Installation

1. Build the app using one of the methods above
2. Copy `ReFinder.app` to `/Applications`
3. Launch the app
4. When prompted, grant Accessibility permissions in System Settings → Privacy & Security → Accessibility
5. Restart the app after granting permissions

## Usage

After launching, a folder icon appears in the menu bar:

- **Enabled**: Toggle the interception on/off
- **Block Finder (do nothing)**: Sets mode to simply block Finder clicks
- **Open Alternative App...**: Choose your preferred file manager
- **About**: Shows version information
- **Quit**: Exit the application

## Starting at Login

To have ReFinder start automatically:

1. Open System Settings → General → Login Items
2. Click "+" and select ReFinder.app
3. Or drag ReFinder.app to the Login Items list

## Troubleshooting

### App doesn't intercept clicks

1. Make sure Accessibility permissions are granted
2. Go to System Settings → Privacy & Security → Accessibility
3. Remove ReFinder and add it again
4. Restart the app

### App lost permissions after macOS update

This is a known macOS behavior. Simply re-grant Accessibility permissions.

### Event tap disabled

macOS may disable the event tap if the app takes too long to process events. The app automatically re-enables it, but if you notice issues, try restarting the app.

## Technical Notes

- The app must run **without** App Sandbox to access Accessibility API
- Cannot be distributed through Mac App Store (due to non-sandboxed requirement)
- Uses `LSUIElement = true` to be a menu bar only app (no Dock icon)

## Alternative Approaches

If this method doesn't work reliably on your macOS version, consider:

1. **Click2Minimize** (commercial) - Uses similar technique, actively maintained
2. **Click2Hide** (open source) - Similar functionality for hiding windows
3. **BetterTouchTool** - Can create custom actions for Dock interactions

## License

MIT License - See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
