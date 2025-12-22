import Cocoa
import ApplicationServices
import os.log

// Global state accessible from C callback
var globalIsEnabled = true
var globalAlternativeAppPath: String? = nil

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private let logger = Logger(subsystem: "com.example.ReFinder", category: "main")

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Configuration - now using global variables
    var isEnabled: Bool {
        get { globalIsEnabled }
        set { globalIsEnabled = newValue }
    }
    var alternativeAppBundleId: String? = nil
    var alternativeAppPath: String? {
        get { globalAlternativeAppPath }
        set { globalAlternativeAppPath = newValue }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ReFinder: applicationDidFinishLaunching started")

        // Also write to file for debugging
        logToFile("applicationDidFinishLaunching started")

        setupMenuBarItem()
        logger.info("ReFinder: setupMenuBarItem completed")
        logToFile("setupMenuBarItem completed")

        checkAccessibilityPermissions()
        logger.info("ReFinder: checkAccessibilityPermissions completed")
        logToFile("checkAccessibilityPermissions completed")

        setupEventTap()
        logger.info("ReFinder: setupEventTap completed")
        logToFile("setupEventTap completed")

        loadSettings()
        logger.info("ReFinder: loadSettings completed - App fully initialized")
        logToFile("loadSettings completed - App fully initialized")
    }

    private func logToFile(_ message: String) {
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ReFinder-debug.log")
        let timestamp = Date()
        let logMessage = "[\(timestamp)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        removeEventTap()
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBarItem() {
        NSLog("ReFinder: Creating status bar item")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NSLog("ReFinder: Status item created: \(String(describing: statusItem))")

        if let button = statusItem.button {
            NSLog("ReFinder: Setting up button image")
            // Use simple SF Symbol that works
            button.image = NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: "ReFinder")
            button.image?.isTemplate = true
            NSLog("ReFinder: Button image set")
        } else {
            NSLog("ReFinder: ERROR - Status item button is nil!")
        }
        
        let menu = NSMenu()
        
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.state = self.isEnabled ? .on : .off
        menu.addItem(enabledItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let blockItem = NSMenuItem(title: "Block Finder (do nothing)", action: #selector(setBlockMode(_:)), keyEquivalent: "")
        menu.addItem(blockItem)
        
        let redirectItem = NSMenuItem(title: "Open Alternative App...", action: #selector(chooseAlternativeApp(_:)), keyEquivalent: "")
        menu.addItem(redirectItem)
        
        if let appPath = self.alternativeAppPath {
            let currentAppItem = NSMenuItem(title: "Current: \(URL(fileURLWithPath: appPath).lastPathComponent)", action: nil, keyEquivalent: "")
            currentAppItem.isEnabled = false
            menu.addItem(currentAppItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "About ReFinder", action: #selector(showAbout(_:)), keyEquivalent: "")
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        NSLog("ReFinder: Menu assigned to status item. Menu items count: \(menu.items.count)")
        NSLog("ReFinder: Status item is visible: \(statusItem.isVisible)")
    }
    
    private func updateMenu() {
        guard let menu = statusItem.menu else { return }
        
        // Update enabled state
        if let enabledItem = menu.items.first(where: { $0.action == #selector(toggleEnabled(_:)) }) {
            enabledItem.state = self.isEnabled ? .on : .off
        }

        // Remove old "Current:" item and add updated one
        menu.items.removeAll(where: { $0.title.hasPrefix("Current:") })

        if let appPath = self.alternativeAppPath {
            let currentAppItem = NSMenuItem(title: "Current: \(URL(fileURLWithPath: appPath).lastPathComponent)", action: nil, keyEquivalent: "")
            currentAppItem.isEnabled = false
            // Insert after "Open Alternative App..."
            if let redirectIndex = menu.items.firstIndex(where: { $0.action == #selector(chooseAlternativeApp(_:)) }) {
                menu.insertItem(currentAppItem, at: redirectIndex + 1)
            }
        }
        
        // Update button image based on state
        if let button = statusItem.button {
            if self.isEnabled {
                button.image = NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: "ReFinder (Active)")
            } else {
                button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "ReFinder (Inactive)")
            }
            button.image?.isTemplate = true
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        self.isEnabled.toggle()
        saveSettings()
        updateMenu()
    }

    @objc private func setBlockMode(_ sender: NSMenuItem) {
        self.alternativeAppBundleId = nil
        self.alternativeAppPath = nil
        saveSettings()
        updateMenu()
        
        let alert = NSAlert()
        alert.messageText = "Block Mode Enabled"
        alert.informativeText = "Clicking Finder icon in Dock will now do nothing."
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    @objc private func chooseAlternativeApp(_ sender: NSMenuItem) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Alternative File Manager"
        openPanel.allowedContentTypes = [.application]
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            self.alternativeAppPath = url.path
            // Get bundle identifier
            if let bundle = Bundle(url: url) {
                self.alternativeAppBundleId = bundle.bundleIdentifier
            }
            saveSettings()
            updateMenu()
            
            let alert = NSAlert()
            alert.messageText = "Alternative App Set"
            alert.informativeText = "Clicking Finder icon in Dock will now open \(url.lastPathComponent)"
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
    
    @objc private func showAbout(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "ReFinder"
        alert.informativeText = """
            Version 0.0.1

            This app allows you to:
            • Block Finder from opening when clicking its Dock icon
            • Redirect Finder Dock clicks to an alternative file manager

            Requires Accessibility permissions to function.

            https://github.com/barabasz/refinder
            """
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    // MARK: - Accessibility Permissions
    
    private func checkAccessibilityPermissions() {
        NSLog("ReFinder: Checking Accessibility permissions")
        // Don't prompt automatically - just check status
        let accessEnabled = AXIsProcessTrusted()
        NSLog("ReFinder: Accessibility permission status: \(accessEnabled)")

        if !accessEnabled {
            NSLog("ReFinder: Showing Accessibility permission alert")
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                ReFinder needs Accessibility permissions to intercept Dock clicks.
                
                Please go to System Settings → Privacy & Security → Accessibility and enable ReFinder.
                
                You may need to restart the app after granting permission.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
    
    // MARK: - Event Tap
    
    private func setupEventTap() {
        NSLog("ReFinder: Setting up event tap")
        // Create event mask for left mouse down
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)

        // Create event tap with callback - pass tap reference via userInfo for re-enabling
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(bitPattern: 0) // placeholder, will store tap after creation
        ) else {
            NSLog("ReFinder: ERROR - Failed to create event tap. Accessibility permission may be missing.")
            return
        }

        NSLog("ReFinder: Event tap created successfully")

        eventTap = tap

        // Create run loop source and add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        NSLog("ReFinder: Event tap enabled and ready")
    }
    
    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: "isEnabled")
        self.alternativeAppBundleId = defaults.string(forKey: "alternativeAppBundleId")
        self.alternativeAppPath = defaults.string(forKey: "alternativeAppPath")

        // Default to enabled if first launch
        if defaults.object(forKey: "isEnabled") == nil {
            self.isEnabled = true
        }

        updateMenu()
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(self.isEnabled, forKey: "isEnabled")
        defaults.set(self.alternativeAppBundleId, forKey: "alternativeAppBundleId")
        defaults.set(self.alternativeAppPath, forKey: "alternativeAppPath")
    }
}

// MARK: - Event Tap Callback (C-style callback with @convention(c))

let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    NSLog("ReFinder: eventTapCallback invoked! Type: \(type.rawValue)")

    // Check if our interception is enabled
    guard globalIsEnabled else {
        NSLog("ReFinder: Global interception disabled, passing event through")
        return Unmanaged.passRetained(event)
    }

    // Handle tap disabled events (system disables tap if it takes too long)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        NSLog("ReFinder: Event tap disabled by system, attempting to re-enable")
        // Note: We can't easily re-enable from here without the tap reference
        // The app will need to monitor and re-enable from the main code
        return Unmanaged.passRetained(event)
    }

    // Only process left mouse down
    guard type == .leftMouseDown else {
        return Unmanaged.passRetained(event)
    }

    // Get click location
    let clickLocation = event.location
    NSLog("ReFinder: Mouse click detected at x=\(clickLocation.x), y=\(clickLocation.y)")

    // Check if click is on Dock's Finder icon
    let isFinderClick = isClickOnFinderDockIcon(at: clickLocation)
    NSLog("ReFinder: isClickOnFinderDockIcon returned: \(isFinderClick)")

    if isFinderClick {
        NSLog("ReFinder: Finder Dock icon click intercepted!")

        // Handle the redirect/block
        if let appPath = globalAlternativeAppPath {
            // Launch alternative app
            NSLog("ReFinder: Launching alternative app: \(appPath)")
            DispatchQueue.main.async {
                let url = URL(fileURLWithPath: appPath)
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error = error {
                        NSLog("ReFinder: Failed to launch alternative app: \(error)")
                    } else {
                        NSLog("ReFinder: Alternative app launched successfully")
                    }
                }
            }
        } else {
            NSLog("ReFinder: Block mode - not launching any app")
        }

        // Block the original click - return nil to consume the event
        return nil
    }

    // Pass through all other events
    return Unmanaged.passRetained(event)
}

// MARK: - Dock Detection

func isClickOnFinderDockIcon(at point: CGPoint) -> Bool {
    NSLog("ReFinder: Checking if click at (\(point.x), \(point.y)) is on Finder Dock icon")

    // Get Dock process
    guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        NSLog("ReFinder: Could not find Dock process")
        return false
    }
    NSLog("ReFinder: Found Dock process with PID: \(dockApp.processIdentifier)")

    // Check if click is in Dock area
    let inDockArea = isPointInDockArea(point)
    NSLog("ReFinder: Point in Dock area: \(inDockArea)")
    guard inDockArea else {
        return false
    }

    // Use Accessibility API to find what's under the click
    let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)

    // Get the element at the click point
    var elementAtPoint: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &elementAtPoint)

    NSLog("ReFinder: AXUIElementCopyElementAtPosition result: \(result.rawValue)")
    guard result == .success, let element = elementAtPoint else {
        NSLog("ReFinder: Failed to get element at position or element is nil")
        return false
    }

    // Check if this element is Finder's dock icon
    let isFinder = isFinderDockIcon(element)
    NSLog("ReFinder: Element is Finder icon: \(isFinder)")
    return isFinder
}

func isPointInDockArea(_ point: CGPoint) -> Bool {
    // Get screen with Dock
    guard let screen = NSScreen.main else { return false }

    let screenFrame = screen.frame
    let dockHeight: CGFloat = 80  // Approximate, could be dynamic

    NSLog("ReFinder: Screen frame: \(screenFrame), Dock height threshold: \(dockHeight)")

    // Check common Dock positions
    // Bottom Dock
    if point.y <= dockHeight {
        NSLog("ReFinder: Click in bottom Dock area (y=\(point.y) <= \(dockHeight))")
        return true
    }

    // Left Dock
    if point.x <= dockHeight {
        NSLog("ReFinder: Click in left Dock area (x=\(point.x) <= \(dockHeight))")
        return true
    }

    // Right Dock
    if point.x >= screenFrame.width - dockHeight {
        NSLog("ReFinder: Click in right Dock area (x=\(point.x) >= \(screenFrame.width - dockHeight))")
        return true
    }

    NSLog("ReFinder: Click NOT in any Dock area")
    return false
}

func isFinderDockIcon(_ element: AXUIElement) -> Bool {
    // Get the title/description of the element
    var titleValue: CFTypeRef?
    let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
    
    if titleResult == .success, let title = titleValue as? String {
        if title == "Finder" {
            return true
        }
    }
    
    // Also check AXDescription
    var descValue: CFTypeRef?
    let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
    
    if descResult == .success, let desc = descValue as? String {
        if desc.contains("Finder") {
            return true
        }
    }
    
    // Check help attribute
    var helpValue: CFTypeRef?
    let helpResult = AXUIElementCopyAttributeValue(element, kAXHelpAttribute as CFString, &helpValue)
    
    if helpResult == .success, let help = helpValue as? String {
        if help.contains("Finder") {
            return true
        }
    }
    
    // Check if parent has Finder in attributes
    var parentValue: CFTypeRef?
    let parentResult = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue)
    
    if parentResult == .success, let parent = parentValue {
        let parentElement = parent as! AXUIElement
        
        var parentTitle: CFTypeRef?
        if AXUIElementCopyAttributeValue(parentElement, kAXTitleAttribute as CFString, &parentTitle) == .success,
           let title = parentTitle as? String, title == "Finder" {
            return true
        }
    }
    
    return false
}
