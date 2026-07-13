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
        NSApp.mainMenu = buildMainMenu()

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
        let cascadeItem = NSMenuItem(title: "前面アプリをカスケード", action: #selector(cascadeFrontmostApp), keyEquivalent: "c")
        cascadeItem.target = self
        menu.addItem(cascadeItem)
        let cascadeAllItem = NSMenuItem(title: "全てのアプリをカスケード", action: #selector(cascadeAllApps), keyEquivalent: "")
        cascadeAllItem.target = self
        menu.addItem(cascadeAllItem)
        let permissionItem = NSMenuItem(title: "アクセシビリティ権限を確認", action: #selector(checkAccessibility), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
            statusLabel?.stringValue = "\(result.applicationName) の \(result.windowCount) 個のウィンドウをカスケードしました"
        } catch {
            showError(error)
        }
    }

    @objc private func cascadeAllApps() {
        let applications = selectableApplications()
        var succeeded: [CascadeResult] = []
        var failures: [String] = []
        var groupIndex = 0

        for application in applications {
            do {
                succeeded.append(try cascader.cascade(application: application, groupIndex: groupIndex))
                groupIndex += 1
            } catch CascadeError.notEnoughWindows {
                continue
            } catch CascadeError.accessibilityPermissionMissing {
                showError(CascadeError.accessibilityPermissionMissing)
                return
            } catch {
                failures.append(application.localizedName ?? application.bundleIdentifier ?? "Unknown")
            }
        }

        if succeeded.isEmpty && failures.isEmpty {
            statusLabel?.stringValue = "ウィンドウが3つ以上のアプリがありませんでした"
            return
        }

        var message = "\(succeeded.count) 個のアプリをカスケードしました"
        if !failures.isEmpty {
            message += "(失敗: \(failures.joined(separator: ", ")))"
        }
        statusLabel?.stringValue = message
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

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "MacWindowCascader を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        return mainMenu
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
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 198))

        let title = NSTextField(labelWithString: "MacWindowCascader")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: 24, y: 146, width: 400, height: 26)

        let popup = NSPopUpButton(frame: NSRect(x: 24, y: 104, width: 300, height: 28), pullsDown: false)
        appPopup = popup

        let reloadButton = NSButton(title: "更新", target: self, action: #selector(refreshApplicationsFromButton))
        reloadButton.bezelStyle = .rounded
        reloadButton.frame = NSRect(x: 336, y: 102, width: 72, height: 32)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 24, y: 72, width: 572, height: 20)
        self.statusLabel = statusLabel

        let button = NSButton(title: "選択したアプリをカスケード", target: self, action: #selector(cascadeFrontmostApp))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 24, y: 28, width: 200, height: 32)

        let cascadeAllButton = NSButton(title: "全てのアプリをカスケード", target: self, action: #selector(cascadeAllApps))
        cascadeAllButton.bezelStyle = .rounded
        cascadeAllButton.frame = NSRect(x: 232, y: 28, width: 200, height: 32)

        let permissionButton = NSButton(title: "権限を確認", target: self, action: #selector(checkAccessibility))
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: 440, y: 28, width: 120, height: 32)

        contentView.addSubview(title)
        contentView.addSubview(popup)
        contentView.addSubview(reloadButton)
        contentView.addSubview(statusLabel)
        contentView.addSubview(button)
        contentView.addSubview(cascadeAllButton)
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

        if selectedApplication() == nil {
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
            .filter { cascader.normalWindowCount(for: $0) >= 3 }
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
        if AccessibilityPermission.requestWithPrompt() {
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
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestWithPrompt() -> Bool {
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
    case cannotMoveWindows(String)
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
        case .cannotMoveWindows(let appName):
            return "\(appName) のウィンドウを移動できませんでした。アクセシビリティ権限を確認してください。"
        case .notEnoughWindows(let appName, let count):
            return "\(appName) の通常ウィンドウは \(count) 個です。3つ以上あるアプリで実行してください。"
        case .noScreen:
            return "配置先の画面を取得できませんでした。"
        }
    }
}

@MainActor
final class WindowCascader {
    // 複数アプリを続けてカスケードするとき、アプリごとにこの分だけ階段配置全体をずらす
    private let applicationGroupOffset: CGFloat = 120
    private let maxHorizontalStep: CGFloat = 120
    private let maxVerticalStep: CGFloat = 30
    private let windowAspectRatio: CGFloat = 4.0 / 3.0
    private let minWidth: CGFloat = 1000
    private let minHeight: CGFloat = 750

    func cascadeFrontmostApplication() throws -> CascadeResult {
        guard AccessibilityPermission.isTrusted() else {
            NSLog("cascade: not trusted")
            throw CascadeError.accessibilityPermissionMissing
        }

        guard let application = frontmostTargetApplication() else {
            throw CascadeError.noFrontmostApplication
        }

        return try cascadeTrusted(application: application, groupIndex: 0)
    }

    func cascade(application: NSRunningApplication, groupIndex: Int = 0) throws -> CascadeResult {
        guard AccessibilityPermission.isTrusted() else {
            NSLog("cascade: not trusted")
            throw CascadeError.accessibilityPermissionMissing
        }

        return try cascadeTrusted(application: application, groupIndex: groupIndex)
    }

    func normalWindowCount(for application: NSRunningApplication) -> Int {
        guard AccessibilityPermission.isTrusted() else {
            return 0
        }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        return (try? normalWindows(for: applicationElement, applicationName: "")).map { $0.count } ?? 0
    }

    private func cascadeTrusted(application: NSRunningApplication, groupIndex: Int) throws -> CascadeResult {
        let appName = application.localizedName ?? application.bundleIdentifier ?? "対象アプリ"
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = try normalWindows(for: applicationElement, applicationName: appName)
        NSLog("cascade: app=%@ pid=%d normalWindows=%d", appName, application.processIdentifier, windows.count)

        guard windows.count >= 3 else {
            throw CascadeError.notEnoughWindows(appName, windows.count)
        }

        guard let screen = targetScreen(for: windows.first) else {
            throw CascadeError.noScreen
        }

        let groupOffset = applicationGroupOffset * CGFloat(groupIndex)
        let frames = cascadeFrames(windowCount: windows.count, visibleFrame: screen.visibleFrame, groupOffset: groupOffset)
        var movedCount = 0
        for (index, (window, frame)) in zip(windows, frames).enumerated() {
            let axFrame = convertToAccessibilityCoordinates(frame)
            if setWindow(window, frame: axFrame, index: index) {
                movedCount += 1
            }
        }

        guard movedCount > 0 else {
            throw CascadeError.cannotMoveWindows(appName)
        }

        bringToFront(application: application, windows: windows)

        return CascadeResult(applicationName: appName, windowCount: movedCount)
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
            NSLog("cascade: AXWindows read failed app=%@ error=%d", applicationName, result.rawValue)
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

    private func convertToAccessibilityCoordinates(_ frame: CGRect) -> CGRect {
        // AXPosition/AXSize は主画面左上を原点として Y が下向きに増える座標系を使うため、
        // NSScreen の左下原点・Y上向きの座標系から変換する
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return frame
        }
        return CGRect(
            x: frame.origin.x,
            y: primaryScreenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
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

    private func cascadeFrames(windowCount: Int, visibleFrame: CGRect, groupOffset: CGFloat) -> [CGRect] {
        // ウィンドウは 4:3 の縦横比を保ちつつ、画面の縦横それぞれ半分を超えない最大サイズにし、
        // 左下(1枚目)から右上(最後の1枚)へ均等なステップで階段状に並べる。
        // groupOffset は複数アプリを続けてカスケードする際の、アプリ単位の追加ずらし量(右方向のみ)。
        let maxWidth = visibleFrame.width / 2
        let maxHeight = visibleFrame.height / 2
        var width: CGFloat
        var height: CGFloat
        if maxHeight * windowAspectRatio <= maxWidth {
            width = maxHeight * windowAspectRatio
            height = maxHeight
        } else {
            width = maxWidth
            height = maxWidth / windowAspectRatio
        }
        // 画面が小さく計算結果が最小サイズを下回る場合は、最小サイズ(1000x750)を優先する
        width = max(width, minWidth)
        height = max(height, minHeight)
        let horizontalRoom = max(visibleFrame.width - width, 0)
        let verticalRoom = max(visibleFrame.height - height, 0)
        let steps = CGFloat(max(windowCount - 1, 1))
        // 横方向・縦方向とも余裕があっても 1 ステップの最大幅を超えないようにし、
        // 使い切らなかった分は中央に寄せる
        let stepX = min(horizontalRoom / steps, maxHorizontalStep)
        let stepY = min(verticalRoom / steps, maxVerticalStep)
        let usedHorizontalSpan = stepX * steps + width
        let usedVerticalSpan = stepY * steps + height
        let horizontalPadding = max(visibleFrame.width - usedHorizontalSpan, 0) / 2
        let verticalPadding = max(visibleFrame.height - usedVerticalSpan, 0) / 2
        let baseX = visibleFrame.minX + horizontalPadding
        let baseY = visibleFrame.minY + verticalPadding

        return (0..<windowCount).map { index in
            let offsetX = stepX * CGFloat(index) + groupOffset
            let offsetY = stepY * CGFloat(index)
            return CGRect(
                x: baseX + offsetX,
                y: baseY + offsetY,
                width: width,
                height: height
            )
        }
    }

    private func setWindow(_ window: AXUIElement, frame: CGRect, index: Int) -> Bool {
        // サイズ変更で位置がずれるアプリや、一度の指定では反映されないアプリが
        // あるため、位置とサイズを交互に 2 回適用してそろえる
        let positionResult = setPosition(window, frame.origin)
        let sizeResult = setSize(window, frame.size)
        _ = setPosition(window, frame.origin)
        _ = setSize(window, frame.size)

        if positionResult != .success || sizeResult != .success {
            NSLog(
                "cascade: window[%d] set failed position=%d size=%d",
                index, positionResult.rawValue, sizeResult.rawValue
            )
        }
        return positionResult == .success && sizeResult == .success
    }

    private func setPosition(_ window: AXUIElement, _ origin: CGPoint) -> AXError {
        var position = origin
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    }

    private func setSize(_ window: AXUIElement, _ targetSize: CGSize) -> AXError {
        var size = targetSize
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    private func bringToFront(application: NSRunningApplication, windows: [AXUIElement]) {
        for window in windows.reversed() {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        if #available(macOS 14.0, *) {
            // macOS 14 以降はアクティブなアプリから他アプリを activate できないため、
            // 先にアクティブ状態を譲る必要がある
            NSApp.yieldActivation(to: application)
            application.activate(options: .activateAllWindows)
        } else {
            application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
