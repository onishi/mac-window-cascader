import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var appPopup: NSPopUpButton?
    private var statusLabel: NSTextField?
    private var lastTargetApplication: NSRunningApplication?
    private let cascader = WindowCascader()
    private let ignoredBundleIdentifiers = Set([
        "com.apple.systempreferences",
        "com.apple.SystemSettings"
    ])

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Cascade") {
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "Cas"
        }
        statusItem.button?.toolTip = "前面アプリのウィンドウをカスケード配置"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "前面アプリをカスケード", action: #selector(cascadeFrontmostApp), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "アクセシビリティ権限を確認", action: #selector(checkAccessibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu

        showMainWindow()
    }

    @objc private func cascadeFrontmostApp() {
        do {
            let result: CascadeResult
            if let selectedApplication = selectedApplication() {
                result = try cascader.cascade(application: selectedApplication)
            } else if let lastTargetApplication, !lastTargetApplication.isTerminated {
                result = try cascader.cascade(application: lastTargetApplication)
            } else {
                result = try cascader.cascadeFrontmostApplication()
            }
            showMessage(
                title: "配置しました",
                message: "\(result.applicationName) の \(result.windowCount) 個のウィンドウをカスケードしました。"
            )
        } catch {
            showError(error)
        }
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              isSelectableApplication(application) else {
            return
        }
        lastTargetApplication = application
        refreshApplicationList(selecting: application)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if window == nil || window?.isVisible == false {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        if window == nil {
            buildMainWindow()
        }

        refreshApplicationList(selecting: lastTargetApplication)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func buildMainWindow() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 232))

        let title = NSTextField(labelWithString: "MacWindowCascader")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: 24, y: 180, width: 400, height: 26)

        let description = NSTextField(wrappingLabelWithString: "対象アプリを選び、通常ウィンドウが 3 つ以上ある状態で実行してください。")
        description.frame = NSRect(x: 24, y: 146, width: 412, height: 24)

        let popup = NSPopUpButton(frame: NSRect(x: 24, y: 104, width: 300, height: 28), pullsDown: false)
        appPopup = popup

        let reloadButton = NSButton(title: "更新", target: self, action: #selector(refreshApplicationsFromButton))
        reloadButton.bezelStyle = .rounded
        reloadButton.frame = NSRect(x: 336, y: 102, width: 72, height: 32)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: 72, width: 412, height: 20)
        self.statusLabel = statusLabel

        let button = NSButton(title: "選択したアプリをカスケード", target: self, action: #selector(cascadeFrontmostApp))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 24, y: 28, width: 180, height: 32)

        let permissionButton = NSButton(title: "権限を確認", target: self, action: #selector(checkAccessibility))
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: 216, y: 28, width: 120, height: 32)

        contentView.addSubview(title)
        contentView.addSubview(description)
        contentView.addSubview(popup)
        contentView.addSubview(reloadButton)
        contentView.addSubview(statusLabel)
        contentView.addSubview(button)
        contentView.addSubview(permissionButton)

        let newWindow = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "MacWindowCascader"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.contentView = contentView
        window = newWindow
        refreshApplicationList(selecting: lastTargetApplication)
    }

    @objc private func refreshApplicationsFromButton() {
        refreshApplicationList(selecting: selectedApplication() ?? lastTargetApplication)
    }

    private func refreshApplicationList(selecting applicationToSelect: NSRunningApplication?) {
        guard let appPopup else {
            return
        }

        let selectedPID = applicationToSelect?.processIdentifier
        let applications = selectableApplications()

        appPopup.removeAllItems()
        for application in applications {
            let name = application.localizedName ?? application.bundleIdentifier ?? "Unknown"
            appPopup.addItem(withTitle: name)
            appPopup.lastItem?.representedObject = application.processIdentifier
        }

        if let selectedPID,
           let index = applications.firstIndex(where: { $0.processIdentifier == selectedPID }) {
            appPopup.selectItem(at: index)
        } else if !applications.isEmpty {
            appPopup.selectItem(at: 0)
        }

        if let selectedApplication = selectedApplication() {
            statusLabel?.stringValue = "対象: \(selectedApplication.localizedName ?? "Unknown")"
        } else {
            statusLabel?.stringValue = "対象アプリがありません"
        }
    }

    private func selectedApplication() -> NSRunningApplication? {
        guard let pid = appPopup?.selectedItem?.representedObject as? pid_t else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid).flatMap {
            $0.isTerminated ? nil : $0
        }
    }

    private func selectableApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter(isSelectableApplication)
            .sorted {
                ($0.localizedName ?? $0.bundleIdentifier ?? "") < ($1.localizedName ?? $1.bundleIdentifier ?? "")
            }
    }

    private func isSelectableApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
            application.activationPolicy == .regular &&
            application.isTerminated == false &&
            !ignoredBundleIdentifiers.contains(application.bundleIdentifier ?? "")
    }

    @objc private func checkAccessibility() {
        if AccessibilityPermission.requestIfNeeded() {
            showMessage(title: "権限は有効です", message: "このアプリはウィンドウの位置とサイズを変更できます。")
        } else {
            showPermissionMessage(
                title: "権限が必要です",
                message: "システム設定 > プライバシーとセキュリティ > アクセシビリティで MacWindowCascader を許可してください。"
            )
        }
    }

    private func showError(_ error: Error) {
        if case CascadeError.accessibilityPermissionMissing = error {
            showPermissionMessage(title: "カスケードできません", message: error.localizedDescription)
        } else {
            showMessage(title: "カスケードできません", message: error.localizedDescription)
        }
    }

    private func showPermissionMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = """
        \(message)

        許可するアプリ:
        \(Bundle.main.bundlePath)

        設定後は MacWindowCascader を一度終了して開き直してください。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.openSettings()
        }
    }

    private func showMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum AccessibilityPermission {
    static func requestIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]

        for urlString in urls {
            guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else {
                continue
            }
            return
        }
    }
}

struct CascadeResult {
    let applicationName: String
    let windowCount: Int
}

enum CascadeError: LocalizedError {
    case accessibilityPermissionMissing
    case noFrontmostApplication
    case cannotReadWindows(String)
    case notEnoughWindows(String, Int)
    case noScreen

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "アクセシビリティ権限がありません。システム設定でこのアプリを許可してから再実行してください。"
        case .noFrontmostApplication:
            return "対象にできる前面アプリが見つかりませんでした。"
        case .cannotReadWindows(let appName):
            return "\(appName) のウィンドウ一覧を取得できませんでした。"
        case .notEnoughWindows(let appName, let count):
            return "\(appName) の通常ウィンドウは \(count) 個です。3つ以上あるアプリで実行してください。"
        case .noScreen:
            return "配置先の画面を取得できませんでした。"
        }
    }
}

final class WindowCascader {
    private let cascadeOffset: CGFloat = 34
    private let minimumWindowSize = CGSize(width: 640, height: 420)
    private let margin: CGFloat = 24

    func cascadeFrontmostApplication() throws -> CascadeResult {
        guard AccessibilityPermission.requestIfNeeded() else {
            throw CascadeError.accessibilityPermissionMissing
        }

        guard let application = frontmostTargetApplication() else {
            throw CascadeError.noFrontmostApplication
        }

        return try cascadeTrusted(application: application)
    }

    func cascade(application: NSRunningApplication) throws -> CascadeResult {
        guard AccessibilityPermission.requestIfNeeded() else {
            throw CascadeError.accessibilityPermissionMissing
        }

        return try cascadeTrusted(application: application)
    }

    private func cascadeTrusted(application: NSRunningApplication) throws -> CascadeResult {
        let appName = application.localizedName ?? application.bundleIdentifier ?? "対象アプリ"
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = try normalWindows(for: applicationElement, applicationName: appName)

        guard windows.count >= 3 else {
            throw CascadeError.notEnoughWindows(appName, windows.count)
        }

        guard let screen = targetScreen(for: windows.first) else {
            throw CascadeError.noScreen
        }

        let frames = cascadeFrames(windowCount: windows.count, visibleFrame: screen.visibleFrame)
        for (window, frame) in zip(windows, frames) {
            setWindow(window, frame: frame)
        }
        bringToFront(application: application, windows: windows)

        return CascadeResult(applicationName: appName, windowCount: windows.count)
    }

    private func frontmostTargetApplication() -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.isActive && $0.processIdentifier != ownPID }
            .first ?? NSWorkspace.shared.frontmostApplication.flatMap {
                $0.processIdentifier == ownPID ? nil : $0
            }
    }

    private func normalWindows(for application: AXUIElement, applicationName: String) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            throw CascadeError.cannotReadWindows(applicationName)
        }

        return windows.filter { window in
            isNormalWindow(window) && !isMinimized(window)
        }
    }

    private func isNormalWindow(_ window: AXUIElement) -> Bool {
        stringAttribute(window, kAXRoleAttribute) == kAXWindowRole &&
            stringAttribute(window, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }

    private func isMinimized(_ window: AXUIElement) -> Bool {
        boolAttribute(window, kAXMinimizedAttribute, defaultValue: false)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String, defaultValue: Bool) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return defaultValue
        }
        return value as? Bool ?? defaultValue
    }

    private func targetScreen(for firstWindow: AXUIElement?) -> NSScreen? {
        guard let firstWindow, let position = pointAttribute(firstWindow, kAXPositionAttribute) else {
            return NSScreen.main ?? NSScreen.screens.first
        }

        return NSScreen.screens.first { screen in
            screen.frame.contains(position)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = axValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(typedValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func cascadeFrames(windowCount: Int, visibleFrame: CGRect) -> [CGRect] {
        let totalOffset = cascadeOffset * CGFloat(max(windowCount - 1, 0))
        let availableWidth = visibleFrame.width - margin * 2 - totalOffset
        let availableHeight = visibleFrame.height - margin * 2 - totalOffset
        let width = max(minimumWindowSize.width, availableWidth)
        let height = max(minimumWindowSize.height, availableHeight)
        let baseX = visibleFrame.minX + margin
        let baseY = visibleFrame.minY + margin

        return (0..<windowCount).map { index in
            let offset = cascadeOffset * CGFloat(index)
            return CGRect(x: baseX + offset, y: baseY + offset, width: width, height: height)
        }
    }

    private func setWindow(_ window: AXUIElement, frame: CGRect) {
        var size = frame.size
        var position = frame.origin

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        if let positionValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        }
    }

    private func bringToFront(application: NSRunningApplication, windows: [AXUIElement]) {
        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        for window in windows.reversed() {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        if let firstWindow = windows.first {
            AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
