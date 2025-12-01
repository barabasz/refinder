import Cocoa
import ApplicationServices

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Configuration
    static var isEnabled = true
    static var alternativeAppBundleId: String? = nil  // nil = just block, otherwise launch this app
    static var alternativeAppPath: String? = nil
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        checkAccessibilityPermissions()
        setupEventTap()
        loadSettings()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        removeEventTap()
    }
    
    // MARK: - Menu Bar Setup
    
    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: "ReFinder")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.state = AppDelegate.isEnabled ? .on : .off
        menu.addItem(enabledItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let blockItem = NSMenuItem(title: "Block Finder (do nothing)", action: #selector(setBlockMode(_:)), keyEquivalent: "")
        menu.addItem(blockItem)
        
        let redirectItem = NSMenuItem(title: "Open Alternative App...", action: #selector(chooseAlternativeApp(_:)), keyEquivalent: "")
        menu.addItem(redirectItem)
        
        if let appPath = AppDelegate.alternativeAppPath {
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
    }
    
    private func updateMenu() {
        guard let menu = statusItem.menu else { return }
        
        // Update enabled state
        if let enabledItem = menu.items.first(where: { $0.action == #selector(toggleEnabled(_:)) }) {
            enabledItem.state = AppDelegate.isEnabled ? .on : .off
        }
        
        // Remove old "Current:" item and add updated one
        menu.items.removeAll(where: { $0.title.hasPrefix("Current:") })
        
        if let appPath = AppDelegate.alternativeAppPath {
            let currentAppItem = NSMenuItem(title: "Current: \(URL(fileURLWithPath: appPath).lastPathComponent)", action: nil, keyEquivalent: "")
            currentAppItem.isEnabled = false
            // Insert after "Open Alternative App..."
            if let redirectIndex = menu.items.firstIndex(where: { $0.action == #selector(chooseAlternativeApp(_:)) }) {
                menu.insertItem(currentAppItem, at: redirectIndex + 1)
            }
        }
        
        // Update button image based on state
        if let button = statusItem.button {
            if AppDelegate.isEnabled {
                button.image = NSImage(systemSymbolName: "folder.badge.minus", accessibilityDescription: "ReFinder (Active)")
            } else {
                button.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "ReFinder (Inactive)")
            }
            button.image?.isTemplate = true
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        AppDelegate.isEnabled.toggle()
        saveSettings()
        updateMenu()
    }
    
    @objc private func setBlockMode(_ sender: NSMenuItem) {
        AppDelegate.alternativeAppBundleId = nil
        AppDelegate.alternativeAppPath = nil
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
            AppDelegate.alternativeAppPath = url.path
            // Get bundle identifier
            if let bundle = Bundle(url: url) {
                AppDelegate.alternativeAppBundleId = bundle.bundleIdentifier
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
            
            https://github.com/andrzej/ReFinder
            """
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    // MARK: - Accessibility Permissions
    
    private func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
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
        // Create event mask for left mouse down
        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        // Create event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("Failed to create event tap. Accessibility permission may be missing.")
            return
        }
        
        eventTap = tap
        
        // Create run loop source and add to run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        
        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("Event tap created successfully")
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
        AppDelegate.isEnabled = defaults.bool(forKey: "isEnabled")
        AppDelegate.alternativeAppBundleId = defaults.string(forKey: "alternativeAppBundleId")
        AppDelegate.alternativeAppPath = defaults.string(forKey: "alternativeAppPath")
        
        // Default to enabled if first launch
        if defaults.object(forKey: "isEnabled") == nil {
            AppDelegate.isEnabled = true
        }
        
        updateMenu()
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(AppDelegate.isEnabled, forKey: "isEnabled")
        defaults.set(AppDelegate.alternativeAppBundleId, forKey: "alternativeAppBundleId")
        defaults.set(AppDelegate.alternativeAppPath, forKey: "alternativeAppPath")
    }
}

// MARK: - Event Tap Callback (must be a C function)

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    
    // Check if our interception is enabled
    guard AppDelegate.isEnabled else {
        return Unmanaged.passRetained(event)
    }
    
    // Handle tap disabled events (system disables tap if it takes too long)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap
        if let tap = refcon?.assumingMemoryBound(to: CFMachPort.self).pointee {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }
    
    // Only process left mouse down
    guard type == .leftMouseDown else {
        return Unmanaged.passRetained(event)
    }
    
    // Get click location
    let clickLocation = event.location
    
    // Check if click is on Dock's Finder icon
    if isClickOnFinderDockIcon(at: clickLocation) {
        print("Finder Dock icon click intercepted!")
        
        // Handle the redirect/block
        if let appPath = AppDelegate.alternativeAppPath {
            // Launch alternative app
            DispatchQueue.main.async {
                let url = URL(fileURLWithPath: appPath)
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error = error {
                        print("Failed to launch alternative app: \(error)")
                    }
                }
            }
        }
        // Block the original click - return nil to consume the event
        return nil
    }
    
    // Pass through all other events
    return Unmanaged.passRetained(event)
}

// MARK: - Dock Detection

private func isClickOnFinderDockIcon(at point: CGPoint) -> Bool {
    // Get Dock process
    guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
        return false
    }
    
    // Check if click is in Dock area
    guard isPointInDockArea(point) else {
        return false
    }
    
    // Use Accessibility API to find what's under the click
    let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
    
    // Get the element at the click point
    var elementAtPoint: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &elementAtPoint)
    
    guard result == .success, let element = elementAtPoint else {
        return false
    }
    
    // Check if this element is Finder's dock icon
    return isFinderDockIcon(element)
}

private func isPointInDockArea(_ point: CGPoint) -> Bool {
    // Get screen with Dock
    guard let screen = NSScreen.main else { return false }
    
    let screenFrame = screen.frame
    let dockHeight: CGFloat = 80  // Approximate, could be dynamic
    
    // Check common Dock positions
    // Bottom Dock
    if point.y <= dockHeight {
        return true
    }
    
    // Left Dock
    if point.x <= dockHeight {
        return true
    }
    
    // Right Dock
    if point.x >= screenFrame.width - dockHeight {
        return true
    }
    
    return false
}

private func isFinderDockIcon(_ element: AXUIElement) -> Bool {
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
