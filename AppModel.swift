import SwiftUI
import AppKit
import Security
import KeyboardShortcuts
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var executablePath: String = "" {
        didSet {
            littleSnitchPathTestStatusText = ""
            littleSnitchPathTestIsSuccess = nil
            saveState()
        }
    }
    @Published var targetPath: String = "" {
        didSet {
            targetPathTestStatusText = ""
            targetPathTestIsSuccess = nil
            saveState()
        }
    }
    @Published var passwordInput: String = ""
    @Published var keychainStatusText: String = "尚未保存 sudo 密码。"
    
    // 改为结构体数组，支持富文本渲染
    @Published var logs: [LogItem] = []
    
    @Published var isMonitoring: Bool = false
    @Published var endpointStats: [EndpointAggregate] = []
    @Published var filterBattleIPsOnly: Bool = true {
        didSet { saveState() }
    }
    @Published var blockedIPAddresses: Set<String> = [] {
        didSet { saveState() }
    }
    @Published var autoRestoreSecondsText: String = "0.1" {
        didSet { saveState() }
    }
    @Published var activeCandidateLimitText: String = "1" {
        didSet { saveState() }
    }
    @Published var restoreRemainingSeconds: Double = 0
    @Published var currentAppliedHotKeyText: String = "未设置"
    @Published var hotKeyStatusText: String = "尚未设置全局快捷键。"
    @Published var permissionStatusText: String = "尚未确认权限。"
    @Published var littleSnitchPathTestStatusText: String = ""
    @Published var littleSnitchPathTestIsSuccess: Bool? = nil
    @Published var targetPathTestStatusText: String = ""
    @Published var targetPathTestIsSuccess: Bool? = nil
    @Published var enableFloatingButton: Bool = false {
        didSet {
            saveState()
            guard !isRestoringState else { return }
            updateFloatingButtonWindow()
        }
    }
    @Published var autoStartMonitoring: Bool = false {
        didSet {
            saveState()
            guard !isRestoringState else { return }
            if autoStartMonitoring && oldValue != autoStartMonitoring {
                appendLog("已开启自动开始监控，将先执行一次权限确认。")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.autoStartMonitoring else { return }
                        self.confirmPermissions(startMonitoringAfterSuccess: false)
                    }
                }
            }
        }
    }
    @Published var enableHotKeyTrigger: Bool = true {
        didSet {
            saveState()
            guard !isRestoringState else { return }
            refreshCurrentShortcutText()
        }
    }
    @Published var enableMenuBarControl: Bool = false {
        didSet {
            saveState()
            guard !isRestoringState else { return }
            updateMenuBarStatusItem()
        }
    }
    @Published var enableBackgroundActivity: Bool = true {
        didSet {
            saveState()
            guard !isRestoringState else { return }
            updateBackgroundActivityState()
        }
    }
    @Published var oneKeyButtonIsPressed: Bool = false
    @Published var footerErrorText: String = ""
    @Published var littleSnitchPathTestColor: Color = .secondary
    @Published var targetPathTestColor: Color = .secondary
    @Published var passwordFieldIsMasked: Bool = false
    @Published var systemPasswordFeedbackText: String = "未保存密码"
    @Published var systemPasswordFeedbackColor: Color = .orange

    var didShowWelcome: Bool {
        get { defaults.bool(forKey: didShowWelcomeKey) }
        set { defaults.set(newValue, forKey: didShowWelcomeKey) }
    }

    var displayedEndpointStats: [EndpointAggregate] {
        if filterBattleIPsOnly {
            let allowedIPs = Set(limitedBattleCandidateIPs)
            return endpointStats.filter { $0.isBattleCandidate && allowedIPs.contains($0.ipAddress) }
        }
        return endpointStats
    }

    var uniqueEndpointCount: Int { displayedEndpointStats.count }
    var totalHitCount: Int { displayedEndpointStats.reduce(0) { $0 + $1.hitCount } }
    var totalOutboundCount: Int { displayedEndpointStats.reduce(0) { $0 + $1.outboundCount } }
    var totalInboundCount: Int { displayedEndpointStats.reduce(0) { $0 + $1.inboundCount } }
    var blockedIPCount: Int { blockedIPAddresses.count }
    var canTriggerOneKeyAction: Bool { isMonitoring && !controlTargetIPs().isEmpty }

    var restoreStatusText: String {
        if restoreRemainingSeconds > 0 {
            return "将在 \(formatSeconds(restoreRemainingSeconds)) 秒后自动恢复"
        }
        if blockedIPCount > 0 {
            return "已切断，等待手动恢复"
        }
        return "未安排自动恢复"
    }

    var currentIntervalStatusText: String {
        let seconds = parsedAutoRestoreSeconds()
        return seconds > 0 ? "当前间隔为 \(seconds) 秒" : "当前间隔未生效"
    }

    var currentCandidateLimitStatusText: String {
        if !filterBattleIPsOnly {
            return "关闭精准控制时切断所有连接"
        }
        return "控制最近\(parsedActiveCandidateLimit())个活跃的连接"
    }

    var currentCandidateLimitStatusColor: Color {
        filterBattleIPsOnly ? .green : .secondary
    }

    var isCandidateLimitEnabled: Bool {
        filterBattleIPsOnly
    }

    var sidebarBattleStatusText: String {
        if !isMonitoring {
            return "未开启监控"
        }
        let ips = limitedBattleCandidateIPs
        guard !ips.isEmpty else {
            return "未检测到对局IP"
        }
        return "当前对局IP为 \(ips.joined(separator: "、"))"
    }

    var sidebarBattleStatusDetected: Bool {
        isMonitoring && !limitedBattleCandidateIPs.isEmpty
    }

    var battleStatusDotColor: Color {
        if !isMonitoring { return .gray }
        return limitedBattleCandidateIPs.isEmpty ? .orange : .green
    }

    var battleStatusTextColor: Color {
        if !isMonitoring { return .gray }
        return limitedBattleCandidateIPs.isEmpty ? .orange : .green
    }

    var battleStatusNSDotColor: NSColor {
        if !isMonitoring { return .systemGray }
        return limitedBattleCandidateIPs.isEmpty ? .systemOrange : .systemGreen
    }

    var battleStatusNSTextColor: NSColor {
        if !isMonitoring { return .systemGray }
        return limitedBattleCandidateIPs.isEmpty ? .systemOrange : .systemGreen
    }

    var monitoringToggleStatusText: String {
        isMonitoring ? "当前状态：监控中" : "当前状态：监控停止"
    }

    var monitoringToggleStatusColor: Color {
        isMonitoring ? .green : .secondary
    }

    var footerStatusText: String {
        footerErrorText.isEmpty ? sidebarBattleStatusText : footerErrorText
    }

    var footerStatusDotColor: Color {
        footerErrorText.isEmpty ? battleStatusDotColor : .red
    }

    var footerStatusTextColor: Color {
        footerErrorText.isEmpty ? battleStatusTextColor : .red
    }

    var hotKeyCurrentTextColor: Color {
        hotKeyStatusColor
    }

    var hotKeyStatusColor: Color {
        if !enableHotKeyTrigger { return .secondary }
        return currentAppliedHotKeyText == "未设置" ? .orange : .green
    }

    var filterBattleHintText: String {
        filterBattleIPsOnly ? "只控制最新的对局IP，但可能遗漏对局" : "控制所有炉石传说的连接，但可能导致游戏直接退出"
    }

    var filterBattleHintColor: Color {
        .green
    }

    private let defaults = UserDefaults.standard
    private let executablePathKey = "LittleSnitchExecutablePath"
    private let targetPathKey = "HearthstoneTargetPath"
    private let didShowWelcomeKey = "LittleSnitchDidShowWelcome"
    private let filterBattleOnlyKey = "LittleSnitchFilterBattleOnly"
    private let blockedIPsKey = "LittleSnitchBlockedIPs"
    private let restoreBackupPathKey = "LittleSnitchRestoreBackupPath"
    private let autoRestoreSecondsKey = "LittleSnitchAutoRestoreSeconds"
    private let activeCandidateLimitKey = "LittleSnitchActiveCandidateLimit"
    private let enableFloatingButtonKey = "LittleSnitchEnableFloatingButton"
    private let autoStartMonitoringKey = "LittleSnitchAutoStartMonitoring"
    private let enableHotKeyTriggerKey = "LittleSnitchEnableHotKeyTrigger"
    private let enableMenuBarControlKey = "LittleSnitchEnableMenuBarControl"
    private let enableBackgroundActivityKey = "LittleSnitchEnableBackgroundActivity"

    private let keychainService = "LittleSnitchOneClickMonitor"
    private let keychainAccount = "sudo-password"

    private let restoreBackupPath = "/tmp/hearthstone_ls_pre_block.lsbackup"
    private let currentModelPath = "/tmp/hearthstone_ls_current.lsbackup"
    private let modifiedModelPath = "/tmp/hearthstone_ls_modified.lsbackup"

    private var monitorProcess: Process?
    private var monitorStdoutPipe: Pipe?
    private var monitorStderrPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var autoRestoreTimer: Timer?
    private var floatingButtonController: FloatingButtonWindowController?
    private var menuBarStatusItemController: MenuBarStatusItemController?
    private var backgroundActivityToken: NSObjectProtocol?
    private var openMainWindowHandler: (() -> Void)?
    private var isRestoringState = false
    private var didAttemptAutoStartMonitoring = false
    private var hasHandledInitialAppear = false
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    
    // 标记位：是否抓到了缺少权限的报错，防止监控退出时给出泛泛的提示
    private var hasHitAuthError = false

    init() {
        KeyboardShortcuts.onKeyUp(for: .timedBlockRestore) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.enableHotKeyTrigger else { return }
                self.handleGlobalHotKeyTriggered()
            }
        }
    }

    func handleAppear() {
        guard !hasHandledInitialAppear else { return }
        hasHandledInitialAppear = true

        isRestoringState = true
        if let savedPath = defaults.string(forKey: executablePathKey) {
            executablePath = savedPath
        }
        if let savedTarget = defaults.string(forKey: targetPathKey) {
            targetPath = savedTarget
        }
        if defaults.object(forKey: filterBattleOnlyKey) != nil {
            filterBattleIPsOnly = defaults.bool(forKey: filterBattleOnlyKey)
        }
        if let savedBlocked = defaults.array(forKey: blockedIPsKey) as? [String] {
            blockedIPAddresses = Set(savedBlocked)
        }
        if let savedInterval = defaults.string(forKey: autoRestoreSecondsKey), !savedInterval.isEmpty {
            autoRestoreSecondsText = savedInterval
        }
        if let savedCandidateLimit = defaults.string(forKey: activeCandidateLimitKey), !savedCandidateLimit.isEmpty {
            activeCandidateLimitText = savedCandidateLimit
        }
        enableFloatingButton = defaults.bool(forKey: enableFloatingButtonKey)
        autoStartMonitoring = defaults.bool(forKey: autoStartMonitoringKey)
        enableHotKeyTrigger = defaults.object(forKey: enableHotKeyTriggerKey) == nil ? true : defaults.bool(forKey: enableHotKeyTriggerKey)
        enableMenuBarControl = defaults.bool(forKey: enableMenuBarControlKey)
        enableBackgroundActivity = defaults.object(forKey: enableBackgroundActivityKey) == nil ? true : defaults.bool(forKey: enableBackgroundActivityKey)
        isRestoringState = false

        refreshKeychainStatus()
        refreshCurrentShortcutText()
        updateFloatingButtonWindow()

        if logs.isEmpty {
            appendLog("程序已启动")
        }

        updateMenuBarStatusItem()
        scheduleStartupAutoStartWhenSafe()
    }

    private func scheduleStartupAutoStartWhenSafe() {
        guard autoStartMonitoring, !didAttemptAutoStartMonitoring, !isMonitoring else { return }

        if NSApp.isActive {
            performStartupAutoStart()
            return
        }

        guard appDidBecomeActiveObserver == nil else { return }
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performStartupAutoStart()
            }
        }
    }

    private func performStartupAutoStart() {
        guard autoStartMonitoring, !didAttemptAutoStartMonitoring, !isMonitoring else { return }
        didAttemptAutoStartMonitoring = true

        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            appDidBecomeActiveObserver = nil
        }

        appendLog("已启用打开软件时自动开始监控。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.autoStartMonitoring, !self.isMonitoring else { return }
                self.confirmPermissions(startMonitoringAfterSuccess: true)
            }
        }
    }

    func browseExecutablePath() {
        let panel = NSOpenPanel()
        panel.title = "选择 Little Snitch 路径"
        panel.message = "可以选择 Little Snitch.app，也可以选择包内的 littlesnitch 可执行文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            executablePath = url.path
            appendLog("已选择 Little Snitch 路径：\(url.path)")
            let resolved = resolveLittleSnitchExecutablePath(from: url.path)
            if !resolved.isEmpty, resolved != url.path {
                appendLog("已解析 Little Snitch 可执行文件：\(resolved)")
            }
        } else {
            appendLog("已取消选择 Little Snitch 路径")
        }
    }

    func browseTargetPath() {
        let panel = NSOpenPanel()
        panel.title = "选择炉石传说路径"
        panel.message = "请选择 Hearthstone.app 或可执行文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            targetPath = url.path
            appendLog("已选择炉石传说路径：\(url.path)")
            let resolved = resolveTargetExecutablePathForMonitoring(from: url.path)
            if !resolved.isEmpty, resolved != url.path {
                appendLog("已解析炉石传说可执行文件：\(resolved)")
            }
        } else {
            appendLog("已取消选择炉石传说路径")
        }
    }

    func testExecutablePath() {
        testLittleSnitchPath(currentExecutablePath())
    }

    func testTargetPath() {
        testTargetAppPath(currentTargetPath())
    }

    func savePasswordToKeychain() {
        let hasExistingPassword = KeychainHelper.exists(service: keychainService, account: keychainAccount)
        if passwordFieldIsMasked && hasExistingPassword {
            systemPasswordFeedbackText = "已保存密码"
            systemPasswordFeedbackColor = .green
            return
        }

        let password = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try KeychainHelper.save(service: keychainService, account: keychainAccount, value: password)
            refreshKeychainStatus()
            systemPasswordFeedbackText = "已保存密码"
            systemPasswordFeedbackColor = .green
            appendLog("已将 sudo 密码保存到 Keychain", type: .success)
        } catch {
            systemPasswordFeedbackText = "保存密码失败"
            systemPasswordFeedbackColor = .red
            appendLog("保存 Keychain 失败", rawOutput: error.localizedDescription, type: .error)
        }
    }

    func deletePasswordFromKeychain() {
        do {
            try KeychainHelper.delete(service: keychainService, account: keychainAccount)
            refreshKeychainStatus()
            permissionStatusText = "尚未确认权限。"
            systemPasswordFeedbackText = "未保存密码"
            systemPasswordFeedbackColor = .orange
            appendLog("已从 Keychain 删除 sudo 密码", type: .success)
        } catch {
            systemPasswordFeedbackText = "未保存密码"
            systemPasswordFeedbackColor = .orange
            appendLog("删除 Keychain 密码失败", rawOutput: error.localizedDescription, type: .error)
        }
    }

    func confirmPermissions() {
        confirmPermissions(startMonitoringAfterSuccess: false)
    }

    private func confirmPermissions(startMonitoringAfterSuccess: Bool) {
        let resolvedLSPath = resolveLittleSnitchExecutablePath(from: currentExecutablePath())
        guard !resolvedLSPath.isEmpty else {
            appendLog("错误：请先选择有效的 Little Snitch 路径，再确认权限。", type: .error)
            permissionStatusText = "权限确认失败：Little Snitch 路径无效。"
            setFooterError("请先选择 Little Snitch 路径")
            return
        }

        let password: String
        do {
            password = try KeychainHelper.read(service: keychainService, account: keychainAccount)
        } catch {
            appendLog("错误：请先保存 sudo 密码，再确认权限。", type: .error)
            permissionStatusText = "权限确认失败：尚未保存密码。"
            systemPasswordFeedbackText = "未保存密码"
            systemPasswordFeedbackColor = .red
            setFooterError("没有可用的 sudo 密码，请先在软件中输入并保存到 Keychain")
            return
        }

        appendLog("开始确认权限。如出现钥匙串访问提示，请点击“始终允许”。")
        permissionStatusText = "正在确认权限..."
        let tempPath = "/tmp/hearthstone_ls_permission_check.lsbackup"

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                PrivilegedProcessRunner.run(password: password, launchPath: resolvedLSPath, arguments: ["export-model", tempPath])
            }.value

            let success = logPrivilegedResult(title: "确认权限测试", result: result)

            if success {
                permissionStatusText = "权限已确认。后续使用时一般不会再请求。"
                systemPasswordFeedbackText = "确认权限成功"
                systemPasswordFeedbackColor = .green
                clearFooterError()
                try? FileManager.default.removeItem(atPath: tempPath)
                if startMonitoringAfterSuccess && autoStartMonitoring && !isMonitoring {
                    startMonitoring()
                }
            } else {
                if result.output.contains("command line tool is not authorized to make changes") {
                    permissionStatusText = "权限确认失败：未开启命令行访问权限。"
                    systemPasswordFeedbackText = "未开启命令行权限"
                    systemPasswordFeedbackColor = .red
                } else if result.output.contains("incorrect password attempt") || result.output.contains("no password was provided") {
                    permissionStatusText = "权限确认失败：密码错误。"
                    systemPasswordFeedbackText = "密码错误"
                    systemPasswordFeedbackColor = .red
                } else {
                    permissionStatusText = "权限确认失败，请检查密码或授权提示。"
                    systemPasswordFeedbackText = "确认权限失败，请检查密码"
                    systemPasswordFeedbackColor = .red
                    setFooterError("权限确认失败，请检查密码或授权提示。")
                    appendLog("若弹出钥匙串访问提示，请选择“始终允许”。")
                }
            }
        }
    }

    func startMonitoring() {
        let rawLSPath = currentExecutablePath()
        let rawGamePath = currentTargetPath()
        let resolvedLSPath = resolveLittleSnitchExecutablePath(from: rawLSPath)
        let resolvedGameExecPath = resolveTargetExecutablePathForMonitoring(from: rawGamePath)

        guard !rawLSPath.isEmpty else {
            setFooterError("请先选择 Little Snitch 路径")
            appendLog("错误：请先选择 Little Snitch 路径", type: .error)
            return
        }
        guard !rawGamePath.isEmpty else {
            setFooterError("请先选择炉石传说路径")
            appendLog("错误：请先选择炉石传说路径", type: .error)
            return
        }
        guard !resolvedLSPath.isEmpty else {
            setFooterError("Little Snitch 路径无效，请仔细检查路径")
            appendLog("错误：无法从当前 Little Snitch 路径解析出可执行文件 -> \(rawLSPath)", type: .error)
            return
        }
        guard !resolvedGameExecPath.isEmpty else {
            setFooterError("炉石传说路径无效，请仔细检查路径")
            appendLog("错误：无法从当前炉石传说路径解析出可执行文件 -> \(rawGamePath)", type: .error)
            return
        }
        guard FileManager.default.fileExists(atPath: resolvedLSPath) else {
            setFooterError("Little Snitch 路径不可用，请仔细检查路径")
            appendLog("错误：Little Snitch 可执行文件不存在 -> \(resolvedLSPath)", type: .error)
            return
        }
        guard FileManager.default.isExecutableFile(atPath: resolvedLSPath) else {
            setFooterError("Little Snitch 路径不可执行，请仔细检查路径")
            appendLog("错误：Little Snitch 路径不可执行 -> \(resolvedLSPath)", type: .error)
            return
        }
        guard FileManager.default.fileExists(atPath: resolvedGameExecPath) else {
            setFooterError("炉石传说路径不可用，请仔细检查路径")
            appendLog("错误：炉石传说可执行文件不存在 -> \(resolvedGameExecPath)", type: .error)
            return
        }

        let password: String
        do {
            password = try KeychainHelper.read(service: keychainService, account: keychainAccount)
        } catch {
            setFooterError("没有可用的 sudo 密码，请先在软件中输入并保存到 Keychain")
            appendLog("错误：还没有可用的 sudo 密码，请先在软件中输入并保存到 Keychain", type: .error)
            return
        }

        clearFooterError()
        stopMonitoring(userInitiated: false)
        clearStats(logIt: false)
        hasHitAuthError = false

        appendLog("用户选择的 Little Snitch 路径：\(rawLSPath)")
        appendLog("解析后的 Little Snitch 可执行文件：\(resolvedLSPath)")
        appendLog("用户选择的炉石传说路径：\(rawGamePath)")
        appendLog("实时监控使用的炉石可执行文件：\(resolvedGameExecPath)")

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        // 核心修复：添加 -k 参数取消 sudo 凭据缓存
        let args = ["-k", "-S", "-p", "", resolvedLSPath, "log-traffic", "--stream"]

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        stdoutBuffer = ""
        stderrBuffer = ""

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.consumeStdoutChunk(chunk, targetExecPath: resolvedGameExecPath)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let chunk = String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.consumeStderrChunk(chunk, targetExecPath: resolvedGameExecPath)
            }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.handleMonitorTermination(status: proc.terminationStatus)
            }
        }

        let commandString = (["/usr/bin/sudo"] + args.map { shellQuote($0) }).joined(separator: " ")
        appendLog("运行命令：\(commandString)")

        do {
            try process.run()

            monitorProcess = process
            monitorStdoutPipe = stdoutPipe
            monitorStderrPipe = stderrPipe
            isMonitoring = true

            if let data = (password + "\n").data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()

            appendLog("开始监控：\(resolvedGameExecPath)", type: .success)
            appendLog("监控命令已静默启动，不会弹出终端窗口。")
            beginBackgroundActivityIfNeeded()
        } catch {
            setFooterError("启动监控失败：\(error.localizedDescription)")
            appendLog("启动监控失败", rawOutput: error.localizedDescription, type: .error)
            cleanupMonitorResources()
        }
    }

    func stopMonitoring(userInitiated: Bool) {
        if userInitiated {
            appendLog("收到停止监控请求")
        }

        monitorStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        monitorStderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process = monitorProcess, process.isRunning {
            process.terminate()
        }

        cleanupMonitorResources()
        isMonitoring = false
        clearFooterError()
        endBackgroundActivityIfNeeded()

        if userInitiated {
            appendLog("监控已结束")
        }
    }

    func triggerOneKeyAction(triggerSource: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            oneKeyButtonIsPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.oneKeyButtonIsPressed = false
                }
            }
        }
        performTimedBlockAndRestore(triggerSource: triggerSource)
    }

    func performTimedBlockAndRestore(triggerSource: String) {
        let seconds = parsedAutoRestoreSeconds()
        guard seconds > 0 else {
            appendLog("错误：自动恢复时间必须是大于 0 的秒数，可输入小数。", type: .error)
            return
        }

        if blockedIPCount > 0 {
            appendLog("检测到已有切断中的 IP，先恢复旧规则后重新执行。")
            _ = restoreBlockedIPsInternal(triggerSource: "preflight")
        }

        let success = blockCurrentIPsInternal(triggerSource: triggerSource)
        if success {
            scheduleAutoRestore(after: seconds)
        }
    }

    func restoreBlockedIPs() {
        _ = restoreBlockedIPsInternal(triggerSource: "manual")
    }

    private func blockCurrentIPsInternal(triggerSource: String) -> Bool {
        let ipList = controlTargetIPs()
        guard !ipList.isEmpty else {
            appendLog("没有可切断的 IP。当前筛选条件下没有目标。")
            return false
        }

        let resolvedLSPath = resolveLittleSnitchExecutablePath(from: currentExecutablePath())
        guard !resolvedLSPath.isEmpty else {
            appendLog("错误：无法解析 Little Snitch 可执行文件路径", type: .error)
            return false
        }

        let password: String
        do {
            password = try KeychainHelper.read(service: keychainService, account: keychainAccount)
        } catch {
            appendLog("错误：还没有可用的 sudo 密码，请先在软件中输入并保存到 Keychain", type: .error)
            return false
        }

        appendLog("准备通过 Little Snitch 切断 \(ipList.count) 个 IP：\(ipList.joined(separator: ", "))（来源：\(triggerSource)）")

        if blockedIPAddresses.isEmpty {
            let backupResult = runPrivilegedProcess(password: password, launchPath: resolvedLSPath, arguments: ["export-model", restoreBackupPath])
            guard logPrivilegedResult(title: "导出切断前模型备份", result: backupResult) else {
                appendLog("无法导出切断前模型，已停止。", type: .error)
                return false
            }
            defaults.set(restoreBackupPath, forKey: restoreBackupPathKey)
        }

        let exportResult = runPrivilegedProcess(password: password, launchPath: resolvedLSPath, arguments: ["export-model", currentModelPath])
        guard logPrivilegedResult(title: "导出当前模型", result: exportResult) else {
            appendLog("导出当前模型失败，已停止。", type: .error)
            return false
        }

        do {
            try addDenyRulesToModel(at: currentModelPath, outputPath: modifiedModelPath, ipList: ipList)
            appendLog("已写入修改后的 Little Snitch 模型：\(modifiedModelPath)", type: .success)
        } catch {
            appendLog("修改 Little Snitch 模型失败", rawOutput: error.localizedDescription, type: .error)
            return false
        }

        let restoreResult = runPrivilegedProcess(password: password, launchPath: resolvedLSPath, arguments: ["restore-model", modifiedModelPath])
        guard logPrivilegedResult(title: "恢复修改后的模型", result: restoreResult) else {
            appendLog("恢复修改后的模型失败，规则未生效。", type: .error)
            return false
        }

        blockedIPAddresses.formUnion(ipList)
        appendLog("已通过 Little Snitch 请求切断 \(ipList.count) 个 IP。\(filterBattleIPsOnly ? "当前仅对‘无 URL 的对局 IP’生效。" : "当前对监控列表中所有 IP 生效。")", type: .success)
        return true
    }

    private func restoreBlockedIPsInternal(triggerSource: String) -> Bool {
        cancelAutoRestore(log: false)

        guard blockedIPCount > 0 else {
            appendLog("当前没有通过程序切断的 IP，无需恢复。")
            return false
        }

        let resolvedLSPath = resolveLittleSnitchExecutablePath(from: currentExecutablePath())
        guard !resolvedLSPath.isEmpty else {
            appendLog("错误：无法解析 Little Snitch 可执行文件路径", type: .error)
            return false
        }

        let password: String
        do {
            password = try KeychainHelper.read(service: keychainService, account: keychainAccount)
        } catch {
            appendLog("错误：还没有可用的 sudo 密码，请先在软件中输入并保存到 Keychain", type: .error)
            return false
        }

        let backupPath = defaults.string(forKey: restoreBackupPathKey) ?? restoreBackupPath
        guard FileManager.default.fileExists(atPath: backupPath) else {
            appendLog("未找到切断前模型备份，无法恢复。备份路径：\(backupPath)", type: .error)
            return false
        }

        appendLog("准备恢复 \(blockedIPCount) 个已切断 IP。（来源：\(triggerSource)）")
        let restoreResult = runPrivilegedProcess(password: password, launchPath: resolvedLSPath, arguments: ["restore-model", backupPath])
        guard logPrivilegedResult(title: "恢复切断前模型", result: restoreResult) else {
            appendLog("恢复模型失败。", type: .error)
            return false
        }

        blockedIPAddresses.removeAll()
        defaults.removeObject(forKey: restoreBackupPathKey)
        restoreRemainingSeconds = 0
        appendLog("已通过 Little Snitch 恢复当前通过按钮切断的 IP 连接。", type: .success)
        return true
    }

    @discardableResult
    private func logPrivilegedResult(title: String, result: (exitCode: Int32, output: String)) -> Bool {
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 {
            appendLog("\(title)：成功", rawOutput: output.isEmpty ? nil : output, type: .success)
            return true
        } else {
            if output.contains("incorrect password attempt") || output.contains("no password was provided") {
                appendLog("\(title)失败：sudo密码错误", rawOutput: output, type: .error)
            } else if output.contains("command line tool is not authorized") {
                setFooterError("未开启little snatch的命令行访问权限")
                appendLog("\(title)失败：未开启命令行访问权限。建议：打开 Little Snitch -> Settings -> Security -> 勾选 Allow access via Terminal", rawOutput: output, type: .error)
            } else {
                appendLog("\(title)失败：exit=\(result.exitCode)", rawOutput: output, type: .error)
            }
            return false
        }
    }

    func clearStats() {
        clearStats(logIt: true)
    }

    private func clearStats(logIt: Bool) {
        endpointStats.removeAll()
        if logIt {
            appendLog("统计已清空")
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func beginPasswordEditing() {
        if passwordFieldIsMasked {
            passwordInput = ""
            passwordFieldIsMasked = false
        }
    }

    private func setFooterError(_ text: String) {
        footerErrorText = text
    }

    private func clearFooterError() {
        footerErrorText = ""
    }

    private func parsedAutoRestoreSeconds() -> Double {
        let raw = autoRestoreSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(raw) ?? 0
    }

    private func parsedActiveCandidateLimit() -> Int {
        let raw = activeCandidateLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Int(raw) ?? 1
        return max(1, value)
    }

    private var limitedBattleCandidateIPs: [String] {
        let candidates = endpointStats.filter { $0.isBattleCandidate }
        guard !candidates.isEmpty else { return [] }

        var latestByIP: [String: Date] = [:]
        for item in candidates {
            if let existing = latestByIP[item.ipAddress] {
                if item.lastSeen > existing {
                    latestByIP[item.ipAddress] = item.lastSeen
                }
            } else {
                latestByIP[item.ipAddress] = item.lastSeen
            }
        }

        return latestByIP
            .sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            .prefix(parsedActiveCandidateLimit())
            .map { $0.key }
    }

    private func scheduleAutoRestore(after seconds: Double) {
        cancelAutoRestore(log: false)
        restoreRemainingSeconds = seconds
        appendLog("已安排 \(formatSeconds(seconds)) 秒后自动恢复。")

        let startedAt = Date()
        autoRestoreTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }

                let elapsed = Date().timeIntervalSince(startedAt)
                let remaining = max(0, seconds - elapsed)
                self.restoreRemainingSeconds = remaining

                if remaining <= 0.0001 {
                    timer.invalidate()
                    self.autoRestoreTimer = nil
                    self.restoreRemainingSeconds = 0
                    _ = self.restoreBlockedIPsInternal(triggerSource: "auto")
                }
            }
        }

        if let timer = autoRestoreTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func cancelAutoRestore(log: Bool) {
        autoRestoreTimer?.invalidate()
        autoRestoreTimer = nil
        if restoreRemainingSeconds > 0 && log {
            appendLog("已取消自动恢复计时。")
        }
        restoreRemainingSeconds = 0
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let rounded = (seconds * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.0001 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    private func handleGlobalHotKeyTriggered() {
        appendLog("收到全局快捷键：\(currentAppliedHotKeyText)")
        triggerOneKeyAction(triggerSource: "hotkey")
    }

    func refreshCurrentShortcutText() {
        if !enableHotKeyTrigger {
            if let shortcut = KeyboardShortcuts.getShortcut(for: .timedBlockRestore) {
                currentAppliedHotKeyText = shortcut.description
            } else {
                currentAppliedHotKeyText = "未设置"
            }
            hotKeyStatusText = "快捷键拔线已关闭"
            return
        }

        if let shortcut = KeyboardShortcuts.getShortcut(for: .timedBlockRestore) {
            currentAppliedHotKeyText = shortcut.description
            hotKeyStatusText = "当前快捷键为 \(shortcut.description)"
        } else {
            currentAppliedHotKeyText = "未设置"
            hotKeyStatusText = "未设置快捷键"
        }
    }

    func toggleMonitoringFromMenuBar(_ enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring(userInitiated: true)
        }
    }

    func registerOpenMainWindowHandler(_ handler: @escaping () -> Void) {
        openMainWindowHandler = handler
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        openMainWindowHandler?()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    func menuBarTemplateImage() -> NSImage? {
        if let image = NSImage(named: "MenuBarLogoTemplate") ?? Bundle.main.image(forResource: "MenuBarLogoTemplate") {
            image.isTemplate = true
            return image
        }
        return nil
    }

    private func updateMenuBarStatusItem() {
        if enableMenuBarControl {
            if menuBarStatusItemController == nil {
                menuBarStatusItemController = MenuBarStatusItemController(model: self)
            }
            menuBarStatusItemController?.show()
        } else {
            menuBarStatusItemController?.hide()
        }
    }

    private func updateFloatingButtonWindow() {
        if enableFloatingButton {
            if floatingButtonController == nil {
                floatingButtonController = FloatingButtonWindowController(model: self)
            }
            floatingButtonController?.show()
        } else {
            floatingButtonController?.hide()
        }
    }

    private func controlTargetIPs() -> [String] {
        if filterBattleIPsOnly {
            return limitedBattleCandidateIPs
        }
        return Array(Set(endpointStats.map { $0.ipAddress })).sorted()
    }

    private func cleanupMonitorResources() {
        monitorStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        monitorStderrPipe?.fileHandleForReading.readabilityHandler = nil
        monitorProcess = nil
        monitorStdoutPipe = nil
        monitorStderrPipe = nil
        stdoutBuffer = ""
        stderrBuffer = ""
    }

    private func handleMonitorTermination(status: Int32) {
        let wasMonitoring = isMonitoring
        
        // 1. 立刻解除异步读取句柄，防止与下方的同步读取产生线程竞争
        monitorStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        monitorStderrPipe?.fileHandleForReading.readabilityHandler = nil
        
        // 2. 强行读取并清空残留数据，应对进程闪退时还没来得及触发 handler 的情况
        if let stderrHandle = monitorStderrPipe?.fileHandleForReading {
            let data = stderrHandle.readDataToEndOfFile()
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                stderrBuffer += str
            }
        }
        if !stderrBuffer.isEmpty {
            handleMonitorLine(stderrBuffer, targetExecPath: "", fromStdErr: true)
            stderrBuffer = ""
        }

        if let stdoutHandle = monitorStdoutPipe?.fileHandleForReading {
            let data = stdoutHandle.readDataToEndOfFile()
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                stdoutBuffer += str
            }
        }
        if !stdoutBuffer.isEmpty {
            handleMonitorLine(stdoutBuffer, targetExecPath: "", fromStdErr: false)
            stdoutBuffer = ""
        }

        cleanupMonitorResources()
        isMonitoring = false
        endBackgroundActivityIfNeeded()

        if wasMonitoring {
            appendLog("监控进程已退出，exit=\(status)", type: status == 0 ? .info : .error)
        }

        // 如果并非自然停止且没有被单独处理过 Auth Error，再输出通用兜底报错
        if status != 0 {
            if !hasHitAuthError {
                appendLog("提示：如果看到密码错误或权限错误，请重新保存 Keychain 密码后再试。", type: .error)
            }
        }
    }

    private func consumeStdoutChunk(_ chunk: String, targetExecPath: String) {
        stdoutBuffer += chunk
        
        if stdoutBuffer.contains("command line tool is not authorized") ||
           stdoutBuffer.contains("incorrect password attempt") ||
           stdoutBuffer.contains("no password was provided") {
            hasHitAuthError = true
            handleMonitorLine(stdoutBuffer, targetExecPath: targetExecPath, fromStdErr: false)
            stdoutBuffer = ""
            return
        }

        while let range = stdoutBuffer.range(of: "\n") {
            let line = String(stdoutBuffer[..<range.lowerBound])
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...range.lowerBound)
            handleMonitorLine(line, targetExecPath: targetExecPath, fromStdErr: false)
        }
    }

    private func consumeStderrChunk(_ chunk: String, targetExecPath: String) {
        stderrBuffer += chunk

        if stderrBuffer.contains("command line tool is not authorized") ||
           stderrBuffer.contains("incorrect password attempt") ||
           stderrBuffer.contains("no password was provided") {
            hasHitAuthError = true
            handleMonitorLine(stderrBuffer, targetExecPath: targetExecPath, fromStdErr: true)
            stderrBuffer = ""
            return
        }

        while let range = stderrBuffer.range(of: "\n") {
            let line = String(stderrBuffer[..<range.lowerBound])
            stderrBuffer.removeSubrange(stderrBuffer.startIndex...range.lowerBound)
            handleMonitorLine(line, targetExecPath: targetExecPath, fromStdErr: true)
        }
    }

    private func handleMonitorLine(_ line: String, targetExecPath: String, fromStdErr: Bool) {
        let trimmed = sanitizeMonitorLine(line)
        guard !trimmed.isEmpty else { return }
        
        // 【核心修复】无论是来自 stdout 还是 stderr，只要检测到了没权限的核心字符串，一律拦截！
        if trimmed.contains("command line tool is not authorized") {
            hasHitAuthError = true
            setFooterError("未开启little snatch的命令行访问权限")
            appendLog("监控报错：未开启命令行访问权限。建议：打开 Little Snitch -> Settings -> Security -> 勾选 Allow access via Terminal", rawOutput: trimmed, type: .error)
            return
        }
        
        if trimmed.contains("incorrect password attempt") || trimmed.contains("no password was provided") {
            hasHitAuthError = true
            appendLog("监控报错：sudo密码错误", rawOutput: trimmed, type: .error)
            return
        }

        if fromStdErr {
            appendLog("监控输出标准错误 (stderr)", rawOutput: trimmed, type: .error)
            return
        }

        if let logRecord = parseLogTrafficRecord(from: trimmed), isRecordForTarget(logRecord, targetExecPath: targetExecPath) {
            if shouldCount(logRecord: logRecord) {
                recordLiveTraffic(logRecord)
            }
            return
        }
    }

    private func sanitizeMonitorLine(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let firstDigit = trimmed.firstIndex(where: { $0.isNumber }) {
            let prefix = trimmed[..<firstDigit]
            if !prefix.isEmpty && prefix.allSatisfy({ !$0.isNumber && !$0.isLetter }) {
                trimmed = String(trimmed[firstDigit...])
            }
        }
        return trimmed
    }

    private func parseLogTrafficRecord(from line: String) -> LogTrafficRecord? {
        let fields = parseCSVLine(line)
        guard fields.count >= 12 else { return nil }

        let timestamp = fields[0]
        let directionRaw = fields[1].lowercased()
        let uid = Int(fields[2]) ?? -1
        let ipAddress = fields[3]
        let remoteHostname = fields[4]
        let protocolNumber = Int(fields[5]) ?? -1
        let port = Int(fields[6]) ?? -1
        let connectCount = Int(fields[7]) ?? 0
        let denyCount = Int(fields[8]) ?? 0
        let byteCountIn = Int(fields[9]) ?? 0
        let byteCountOut = Int(fields[10]) ?? 0
        let connectingExecutable = fields[11]
        let parentAppExecutable = fields.count > 12 ? fields[12] : ""

        guard !timestamp.isEmpty,
              !ipAddress.isEmpty,
              port >= 0,
              !connectingExecutable.isEmpty else {
            return nil
        }

        let direction: TrafficDirection
        switch directionRaw {
        case "in": direction = .inbound
        case "out": direction = .outbound
        default: return nil
        }

        return LogTrafficRecord(
            timestamp: timestamp,
            direction: direction,
            uid: uid,
            ipAddress: ipAddress,
            remoteHostname: remoteHostname,
            protocolNumber: protocolNumber,
            port: port,
            connectCount: connectCount,
            denyCount: denyCount,
            byteCountIn: byteCountIn,
            byteCountOut: byteCountOut,
            connectingExecutable: connectingExecutable,
            parentAppExecutable: parentAppExecutable
        )
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = line.index(after: next)
                    continue
                } else {
                    inQuotes.toggle()
                }
            } else if ch == ",", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }

    private func isRecordForTarget(_ logRecord: LogTrafficRecord, targetExecPath: String) -> Bool {
        if logRecord.connectingExecutable == targetExecPath || logRecord.parentAppExecutable == targetExecPath {
            return true
        }

        let targetName = URL(fileURLWithPath: targetExecPath).lastPathComponent.lowercased()
        let connectingName = URL(fileURLWithPath: logRecord.connectingExecutable).lastPathComponent.lowercased()
        let parentName = URL(fileURLWithPath: logRecord.parentAppExecutable).lastPathComponent.lowercased()
        return !targetName.isEmpty && (connectingName == targetName || parentName == targetName)
    }

    private func shouldCount(logRecord: LogTrafficRecord) -> Bool {
        logRecord.connectCount > 0 || logRecord.byteCountIn > 0 || logRecord.byteCountOut > 0
    }

    private func recordLiveTraffic(_ logRecord: LogTrafficRecord) {
        let endpointText = displayEndpoint(ipAddress: logRecord.ipAddress, remoteHostname: logRecord.remoteHostname)
        let event = TrafficEvent(
            endpoint: endpointText,
            ipAddress: logRecord.ipAddress,
            remoteHostname: logRecord.remoteHostname,
            port: logRecord.port,
            protocolName: protocolName(from: logRecord.protocolNumber),
            direction: logRecord.direction,
            processName: URL(fileURLWithPath: logRecord.connectingExecutable).lastPathComponent,
            rawLine: logRecord.timestamp
        )
        self.record(event)
    }

    private func displayEndpoint(ipAddress: String, remoteHostname: String) -> String {
        let host = remoteHostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || host == ipAddress {
            return ipAddress
        }
        return "\(ipAddress) (\(host))"
    }

    private func protocolName(from protocolNumber: Int) -> String {
        switch protocolNumber {
        case 6: return "TCP"
        case 17: return "UDP"
        default: return String(protocolNumber)
        }
    }

    private func record(_ event: TrafficEvent) {
        let kind = EndpointKind.classify(event.ipAddress)
        let key = aggregateKey(for: event)

        if let index = endpointStats.firstIndex(where: { $0.aggregateKey == key }) {
            endpointStats[index].hitCount += 1
            endpointStats[index].lastSeen = event.time
            endpointStats[index].ports.insert(event.port)
            endpointStats[index].protocols.insert(event.protocolName)
            endpointStats[index].remoteHostname = chooseRicherHostname(existing: endpointStats[index].remoteHostname, incoming: event.remoteHostname)
            endpointStats[index].endpoint = displayEndpoint(ipAddress: endpointStats[index].ipAddress, remoteHostname: endpointStats[index].remoteHostname)
            endpointStats[index].kind = EndpointKind.classify(endpointStats[index].ipAddress)

            switch event.direction {
            case .inbound:
                endpointStats[index].inboundCount += 1
            case .outbound:
                endpointStats[index].outboundCount += 1
            }
        } else {
            var item = EndpointAggregate(
                aggregateKey: key,
                endpoint: event.endpoint,
                ipAddress: event.ipAddress,
                remoteHostname: event.remoteHostname,
                kind: kind,
                primaryPort: event.port,
                primaryProtocol: event.protocolName,
                hitCount: 1,
                inboundCount: 0,
                outboundCount: 0,
                ports: [event.port],
                protocols: [event.protocolName],
                lastSeen: event.time
            )
            switch event.direction {
            case .inbound:
                item.inboundCount = 1
            case .outbound:
                item.outboundCount = 1
            }
            endpointStats.append(item)
        }

        endpointStats.sort {
            if $0.hitCount != $1.hitCount { return $0.hitCount > $1.hitCount }
            if $0.endpoint != $1.endpoint { return $0.endpoint < $1.endpoint }
            if $0.primaryProtocol != $1.primaryProtocol { return $0.primaryProtocol < $1.primaryProtocol }
            return $0.primaryPort < $1.primaryPort
        }
    }

    private func chooseRicherHostname(existing: String, incoming: String) -> String {
        let old = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if old.isEmpty { return new }
        if new.isEmpty { return old }
        return old.count >= new.count ? old : new
    }

    private func aggregateKey(for event: TrafficEvent) -> String {
        "\(event.ipAddress)|\(event.protocolName.uppercased())|\(event.port)"
    }

    private func addDenyRulesToModel(at inputPath: String, outputPath: String, ipList: [String]) throws {
        let url = URL(fileURLWithPath: inputPath)
        let data = try Data(contentsOf: url)
        guard var model = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelEditError.invalidTopLevelObject
        }
        guard var rules = model["rules"] as? [[String: Any]] else {
            throw ModelEditError.rulesArrayNotFound
        }

        let existingIPs = Set(rules.compactMap { rule -> String? in
            guard let action = rule["action"] as? String, action == "deny",
                  let origin = rule["origin"] as? String, origin == "frontend",
                  let remote = rule["remote-addresses"] as? String,
                  let uid = rule["uid"] as? Int, uid == currentUID() else {
                return nil
            }
            return remote
        })

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())

        for ip in ipList where !existingIPs.contains(ip) {
            let rule: [String: Any] = [
                "action": "deny",
                "creationDate": now,
                "modificationDate": now,
                "origin": "frontend",
                "remote-addresses": ip,
                "uid": currentUID()
            ]
            rules.append(rule)
        }

        model["rules"] = rules
        let outputData = try JSONSerialization.data(withJSONObject: model, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    private func runPrivilegedProcess(password: String, launchPath: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        PrivilegedProcessRunner.run(password: password, launchPath: launchPath, arguments: arguments)
    }

    private func currentUID() -> Int {
        Int(getuid())
    }

    private func testLittleSnitchPath(_ path: String) {
        littleSnitchPathTestStatusText = ""
        littleSnitchPathTestIsSuccess = nil
        littleSnitchPathTestColor = .secondary

        guard !path.isEmpty else {
            littleSnitchPathTestStatusText = "路径为空。"
            littleSnitchPathTestIsSuccess = false
            littleSnitchPathTestColor = .red
            return
        }

        let resolved = resolveLittleSnitchExecutablePath(from: path)
        if resolved.isEmpty {
            littleSnitchPathTestStatusText = "无法解析出可执行文件。"
            littleSnitchPathTestIsSuccess = false
            littleSnitchPathTestColor = .red
            return
        }

        if FileManager.default.isExecutableFile(atPath: resolved) {
            let hintTarget = path + " " + resolved
            if hintTarget.localizedCaseInsensitiveContains("Little Snitch.app") {
                if resolved == path {
                    littleSnitchPathTestStatusText = "路径有效。"
                } else {
                    littleSnitchPathTestStatusText = "已解析为：\(resolved)"
                }
                littleSnitchPathTestColor = .green
            } else {
                littleSnitchPathTestStatusText = "没有检测到 Little Snitch.app, 但不影响运行，请仔细检查路径"
                littleSnitchPathTestColor = .orange
            }
            littleSnitchPathTestIsSuccess = true
        } else {
            littleSnitchPathTestStatusText = "路径不可执行。"
            littleSnitchPathTestIsSuccess = false
            littleSnitchPathTestColor = .red
        }
    }

    private func testTargetAppPath(_ path: String) {
        targetPathTestStatusText = ""
        targetPathTestIsSuccess = nil
        targetPathTestColor = .secondary

        guard !path.isEmpty else {
            targetPathTestStatusText = "路径为空。"
            targetPathTestIsSuccess = false
            targetPathTestColor = .red
            return
        }

        let resolvedApp = resolveTargetExecutablePath(from: path)
        let resolvedExec = resolveTargetExecutablePathForMonitoring(from: path)

        if resolvedApp.isEmpty {
            targetPathTestStatusText = "无法解析出炉石目标。"
            targetPathTestIsSuccess = false
            targetPathTestColor = .red
            return
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolvedApp, isDirectory: &isDirectory)
        if !exists {
            targetPathTestStatusText = "目标不存在。"
            targetPathTestIsSuccess = false
            targetPathTestColor = .red
            return
        }

        let hintTarget = path + " " + resolvedApp + " " + resolvedExec
        if hintTarget.localizedCaseInsensitiveContains("Hearthstone.app") {
            if isDirectory.boolValue {
                targetPathTestStatusText = "App 路径有效。"
            } else if FileManager.default.isExecutableFile(atPath: resolvedApp) {
                targetPathTestStatusText = "可执行文件有效。"
            } else {
                targetPathTestStatusText = "目标存在。"
            }

            if !resolvedExec.isEmpty && resolvedExec != resolvedApp {
                targetPathTestStatusText += " 监控使用：\(resolvedExec)"
            }
            targetPathTestColor = .green
        } else {
            targetPathTestStatusText = "没有检测到 Hearthstone.app, 但不影响运行，请仔细检查路径"
            targetPathTestColor = .orange
        }
        targetPathTestIsSuccess = true
    }

    private func resolveLittleSnitchExecutablePath(_ path: String) {
        guard !path.isEmpty else {
            appendLog("错误：炉石传说路径为空", type: .error)
            return
        }

        let resolvedApp = resolveTargetExecutablePath(from: path)
        let resolvedExec = resolveTargetExecutablePathForMonitoring(from: path)

        if resolvedApp.isEmpty {
            appendLog("测试失败：无法从该路径解析出炉石传说目标 -> \(path)", type: .error)
            return
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolvedApp, isDirectory: &isDirectory)
        if !exists {
            appendLog("测试失败：炉石传说目标不存在 -> \(resolvedApp)", type: .error)
            return
        }

        if isDirectory.boolValue {
            appendLog("测试通过：炉石传说 App 路径有效 -> \(resolvedApp)", type: .success)
        } else if FileManager.default.isExecutableFile(atPath: resolvedApp) {
            appendLog("测试通过：炉石传说可执行文件有效 -> \(resolvedApp)", type: .success)
        } else {
            appendLog("测试通过：炉石传说目标存在 -> \(resolvedApp)", type: .success)
        }

        if !resolvedExec.isEmpty {
            appendLog("实时监控使用的炉石可执行文件：\(resolvedExec)")
        }
    }

    private func resolveLittleSnitchExecutablePath(from rawPath: String) -> String {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else { return "" }

        if !isDirectory.boolValue {
            return path
        }

        let candidates = [
            (path as NSString).appendingPathComponent("Contents/Components/littlesnitch"),
            (path as NSString).appendingPathComponent("Contents/MacOS/littlesnitch")
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        if path.hasSuffix(".app"),
           let bundle = Bundle(path: path),
           let executableURL = bundle.executableURL,
           FileManager.default.isExecutableFile(atPath: executableURL.path) {
            return executableURL.path
        }

        return ""
    }

    private func resolveTargetExecutablePath(from rawPath: String) -> String {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else { return "" }

        if !isDirectory.boolValue {
            return path
        }

        if path.hasSuffix(".app") {
            return path
        }

        if let bundle = Bundle(path: path), let executableURL = bundle.executableURL {
            return executableURL.path
        }

        return path
    }

    private func resolveTargetExecutablePathForMonitoring(from rawPath: String) -> String {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else { return "" }

        if !isDirectory.boolValue {
            return path
        }

        if path.hasSuffix(".app"),
           let bundle = Bundle(path: path),
           let executableURL = bundle.executableURL,
           FileManager.default.isExecutableFile(atPath: executableURL.path) {
            return executableURL.path
        }

        if let bundle = Bundle(path: path), let executableURL = bundle.executableURL {
            return executableURL.path
        }

        return path
    }

    private func autoDetectLittleSnitchPathIfNeeded() {
        guard currentExecutablePath().isEmpty else { return }

        let candidates = [
            "/Applications/Little Snitch.app/Contents/Components/littlesnitch",
            "/Applications/Little Snitch.app/Contents/MacOS/littlesnitch",
            "/Applications/Little Snitch.app"
        ]

        for candidate in candidates where !resolveLittleSnitchExecutablePath(from: candidate).isEmpty {
            executablePath = candidate
            appendLog("已自动填入 Little Snitch 路径：\(candidate)")
            return
        }
    }

    private func autoDetectHearthstonePathIfNeeded() {
        guard currentTargetPath().isEmpty else { return }

        let candidates = [
            "/Applications/Hearthstone/Hearthstone.app",
            "/Applications/Hearthstone.app",
            "/Applications/Hearthstone/Hearthstone.app/Contents/MacOS/Hearthstone"
        ]

        for candidate in candidates where !resolveTargetExecutablePath(from: candidate).isEmpty {
            targetPath = candidate
            appendLog("已自动填入炉石传说路径：\(candidate)")
            return
        }
    }

    private func refreshKeychainStatus() {
        let exists = KeychainHelper.exists(service: keychainService, account: keychainAccount)
        if exists {
            keychainStatusText = "已检测到保存的 sudo 密码。后续启动监控时会静默使用。"
            if permissionStatusText == "尚未确认权限。" {
                permissionStatusText = "可点击“确认权限”提前完成一次授权测试。"
            }
            if !passwordFieldIsMasked {
                passwordInput = "••••••"
                passwordFieldIsMasked = true
            }
            systemPasswordFeedbackText = "已保存密码"
            systemPasswordFeedbackColor = .green
        } else {
            keychainStatusText = "尚未保存 sudo 密码。首次使用请先输入并保存。"
            permissionStatusText = "尚未确认权限。"
            passwordInput = ""
            passwordFieldIsMasked = false
            systemPasswordFeedbackText = "未保存密码"
            systemPasswordFeedbackColor = .orange
        }
    }

    private func saveState() {
        guard !isRestoringState else { return }
        let path = currentExecutablePath()
        let target = currentTargetPath()

        if !path.isEmpty {
            defaults.set(path, forKey: executablePathKey)
        }
        if !target.isEmpty {
            defaults.set(target, forKey: targetPathKey)
        }
        defaults.set(filterBattleIPsOnly, forKey: filterBattleOnlyKey)
        defaults.set(Array(blockedIPAddresses).sorted(), forKey: blockedIPsKey)
        defaults.set(autoRestoreSecondsText, forKey: autoRestoreSecondsKey)
        defaults.set(activeCandidateLimitText, forKey: activeCandidateLimitKey)
        defaults.set(enableFloatingButton, forKey: enableFloatingButtonKey)
        defaults.set(autoStartMonitoring, forKey: autoStartMonitoringKey)
        defaults.set(enableHotKeyTrigger, forKey: enableHotKeyTriggerKey)
        defaults.set(enableMenuBarControl, forKey: enableMenuBarControlKey)
        defaults.set(enableBackgroundActivity, forKey: enableBackgroundActivityKey)
        defaults.synchronize()
    }

    private func updateBackgroundActivityState() {
        if isMonitoring {
            beginBackgroundActivityIfNeeded()
        } else {
            endBackgroundActivityIfNeeded()
        }
    }

    deinit {
        if let observer = appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let token = backgroundActivityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
    }

    private func beginBackgroundActivityIfNeeded() {
        guard enableBackgroundActivity else { return }
        guard backgroundActivityToken == nil else { return }
        backgroundActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Little Snitch 监控与菜单栏拔线"
        )
        appendLog("已申请后台活动。")
    }

    private func endBackgroundActivityIfNeeded() {
        guard let token = backgroundActivityToken else { return }
        ProcessInfo.processInfo.endActivity(token)
        backgroundActivityToken = nil
        appendLog("已结束后台活动。")
    }

    private func currentExecutablePath() -> String {
        executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentTargetPath() -> String {
        targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    func resetToInitialState() {
        stopMonitoring(userInitiated: false)
        cancelAutoRestore(log: false)
        if blockedIPCount > 0 {
            _ = restoreBlockedIPsInternal(triggerSource: "reset")
        }

        do {
            try KeychainHelper.delete(service: keychainService, account: keychainAccount)
        } catch {
        }

        let keys = [
            executablePathKey,
            targetPathKey,
            didShowWelcomeKey,
            filterBattleOnlyKey,
            blockedIPsKey,
            restoreBackupPathKey,
            autoRestoreSecondsKey,
            activeCandidateLimitKey,
            enableFloatingButtonKey,
            autoStartMonitoringKey,
            enableHotKeyTriggerKey,
            enableMenuBarControlKey,
            enableBackgroundActivityKey
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }

        let tempPaths = [
            restoreBackupPath,
            currentModelPath,
            modifiedModelPath,
            "/tmp/hearthstone_ls_permission_check.lsbackup"
        ]
        for path in tempPaths {
            try? FileManager.default.removeItem(atPath: path)
        }

        isRestoringState = true
        executablePath = ""
        targetPath = ""
        passwordInput = ""
        keychainStatusText = "尚未保存 sudo 密码。"
        logs = []
        isMonitoring = false
        endpointStats = []
        filterBattleIPsOnly = true
        blockedIPAddresses = []
        autoRestoreSecondsText = "0.1"
        activeCandidateLimitText = "1"
        restoreRemainingSeconds = 0
        currentAppliedHotKeyText = "未设置"
        hotKeyStatusText = "尚未设置全局快捷键。"
        permissionStatusText = "尚未确认权限。"
        littleSnitchPathTestStatusText = ""
        littleSnitchPathTestIsSuccess = nil
        littleSnitchPathTestColor = .secondary
        targetPathTestStatusText = ""
        targetPathTestIsSuccess = nil
        targetPathTestColor = .secondary
        passwordFieldIsMasked = false
        systemPasswordFeedbackText = "未保存密码"
        systemPasswordFeedbackColor = .orange
        footerErrorText = ""
        enableFloatingButton = false
        autoStartMonitoring = false
        enableHotKeyTrigger = true
        enableMenuBarControl = false
        enableBackgroundActivity = true
        oneKeyButtonIsPressed = false
        hasHitAuthError = false
        isRestoringState = false

        refreshKeychainStatus()
        refreshCurrentShortcutText()
        updateFloatingButtonWindow()
        updateMenuBarStatusItem()
        defaults.synchronize()
        appendLog("已恢复到初始状态。", type: .success)
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let special = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"\\$`()!&;|<>*?[]{}"))
        if value.rangeOfCharacter(from: special) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    // 核心修改点：使用结构体封装，解耦了缩进和渲染
    private func appendLog(_ text: String, rawOutput: String? = nil, type: LogType = .info) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: Date())
        
        let item = LogItem(
            time: timeString,
            message: text,
            rawOutput: rawOutput,
            type: type
        )
        logs.append(item)
    }
}

// MARK: - 日志类型与结构体定义

enum LogType {
    case info
    case success
    case error

    var color: Color {
        switch self {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }
}

struct LogItem: Identifiable, Equatable {
    let id = UUID()
    let time: String
    let message: String
    let rawOutput: String?
    let type: LogType
}

private enum PrivilegedProcessRunner {
    static func run(password: String, launchPath: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // 核心修复：添加 -k 参数取消 sudo 凭据缓存
        process.arguments = ["-k", "-S", "-p", "", launchPath] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        do {
            try process.run()
            if let data = (password + "\n").data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let output = (String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")
            return (process.terminationStatus, output)
        } catch {
            return (-1, "执行失败：\(error.localizedDescription)")
        }
    }
}

enum TrafficDirection: String, CaseIterable {
    case inbound = "入站"
    case outbound = "出站"
}

enum EndpointKind: String, Hashable {
    case publicIPv4 = "公网 IPv4"
    case privateIPv4 = "私网 IPv4"
    case loopback = "回环地址"
    case linkLocal = "链路本地"
    case hostname = "主机名 / URL"

    static func classify(_ endpoint: String) -> EndpointKind {
        let parts = endpoint.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let a = parts[0]
            let b = parts[1]
            if a == 127 { return .loopback }
            if a == 169 && b == 254 { return .linkLocal }
            if a == 10 { return .privateIPv4 }
            if a == 172 && (16...31).contains(b) { return .privateIPv4 }
            if a == 192 && b == 168 { return .privateIPv4 }
            return .publicIPv4
        }
        return .hostname
    }
}

struct TrafficEvent: Identifiable, Hashable {
    let id = UUID()
    let time = Date()
    let endpoint: String
    let ipAddress: String
    let remoteHostname: String
    let port: Int
    let protocolName: String
    let direction: TrafficDirection
    let processName: String
    let rawLine: String
}

struct EndpointAggregate: Identifiable, Hashable {
    var id: String { aggregateKey }

    let aggregateKey: String
    var endpoint: String
    let ipAddress: String
    var remoteHostname: String
    var kind: EndpointKind
    let primaryPort: Int
    let primaryProtocol: String
    var hitCount: Int
    var inboundCount: Int
    var outboundCount: Int
    var ports: Set<Int>
    var protocols: Set<String>
    var lastSeen: Date

    var hasURL: Bool {
        !remoteHostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isBattleCandidate: Bool {
        !hasURL
    }
}

struct LogTrafficRecord: Hashable {
    let timestamp: String
    let direction: TrafficDirection
    let uid: Int
    let ipAddress: String
    let remoteHostname: String
    let protocolNumber: Int
    let port: Int
    let connectCount: Int
    let denyCount: Int
    let byteCountIn: Int
    let byteCountOut: Int
    let connectingExecutable: String
    let parentAppExecutable: String
}

@MainActor
private final class MenuBarStatusItemController: NSObject {
    private weak var model: AppModel?
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var disconnectItem: NSMenuItem?
    private var modelChangeCancellable: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
        subscribeToModelChanges()
    }

    func show() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem = item
        }
        configureButton()
        if menu == nil {
            buildMenu()
        }
        updateDynamicMenuState()
    }

    func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        menu = nil
        disconnectItem = nil
    }

    private func subscribeToModelChanges() {
        modelChangeCancellable = model?.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDynamicMenuState()
            }
    }

    private func configureButton() {
        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageOnly
        if let image = model?.menuBarTemplateImage() {
            button.image = image
            button.title = ""
        } else {
            let image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "菜单栏拔线")
            image?.isTemplate = true
            button.image = image
            button.title = ""
        }
        button.toolTip = "一键拔线"
    }

    private func buildMenu() {
        guard let item = statusItem, let model else { return }

        let menu = NSMenu()

        let statusView = NSHostingView(
            rootView: MenuBarStatusInfoObservedRow(model: model)
        )
        statusView.frame = NSRect(x: 0, y: 0, width: 260, height: 36)
        let statusMenuItem = NSMenuItem()
        statusMenuItem.view = statusView
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let toggleView = NSHostingView(
            rootView: MenuBarMonitoringToggleObservedRow(model: model)
        )
        toggleView.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
        let toggleItem = NSMenuItem()
        toggleItem.view = toggleView
        menu.addItem(toggleItem)

        let disconnectItem = NSMenuItem(title: "一键拔线", action: #selector(oneKeyDisconnect), keyEquivalent: "")
        disconnectItem.target = self
        menu.addItem(disconnectItem)
        self.disconnectItem = disconnectItem

        menu.addItem(.separator())

        let openMainItem = NSMenuItem(title: "打开主界面", action: #selector(openMainWindow), keyEquivalent: "")
        openMainItem.target = self
        menu.addItem(openMainItem)

        item.menu = menu
        self.menu = menu
    }

    private func updateDynamicMenuState() {
        configureButton()
        disconnectItem?.isEnabled = model?.canTriggerOneKeyAction ?? false
        if let menu {
            menu.update()
        }
    }

    @objc private func oneKeyDisconnect() {
        model?.triggerOneKeyAction(triggerSource: "menubar")
    }

    @objc private func openMainWindow() {
        model?.showMainWindow()
    }
}

struct UnifiedFooterStatusRow: View {
    @ObservedObject var model: AppModel
    var circleSize: CGFloat = 9
    var textFont: Font = .caption
    var lineLimit: Int = 3
    var fixedWidth: CGFloat? = nil
    var horizontalPadding: CGFloat = 0
    var verticalPadding: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(model.footerStatusDotColor)
                .frame(width: circleSize, height: circleSize)
                .padding(.top, 4)
            Text(model.footerStatusText)
                .font(textFont)
                .foregroundStyle(model.footerStatusTextColor)
                .multilineTextAlignment(.leading)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(width: fixedWidth, alignment: .leading)
    }
}

private struct MenuBarStatusInfoObservedRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        UnifiedFooterStatusRow(
            model: model,
            circleSize: 8,
            textFont: .system(size: 12),
            lineLimit: 2,
            fixedWidth: 260,
            horizontalPadding: 12,
            verticalPadding: 8
        )
    }
}

private struct MenuBarMonitoringToggleObservedRow: View {
    @ObservedObject var model: AppModel
    @State private var isBusy = false

    var body: some View {
        HStack(spacing: 8) {
            Text(model.isMonitoring ? "监控中" : "监控停止")
                .font(.system(size: 13))
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { model.isMonitoring },
                set: { newValue in
                    guard !isBusy else { return }
                    isBusy = true
                    DispatchQueue.main.async {
                        model.toggleMonitoringFromMenuBar(newValue)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isBusy = false
                        }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 260, alignment: .leading)
    }
}

private final class FloatingButtonWindowController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        updateContent()
        placePanel()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 190, height: 74),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        self.panel = panel
        updateContent()
        placePanel()
    }

    private func updateContent() {
        guard let panel, let model else { return }
        panel.contentView = NSHostingView(rootView: FloatingButtonView(model: model))
    }

    private func placePanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: visible.maxX - panel.frame.width - 20, y: visible.maxY - panel.frame.height - 20)
        panel.setFrameOrigin(origin)
    }
}

private struct FloatingButtonView: View {
    @ObservedObject var model: AppModel
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            model.triggerOneKeyAction(triggerSource: "floating")
        }) {
            Text("一键拔线")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .contentShape(Capsule()) // 确保整个内边距区域可点击
        }
        .background(buttonColor)
        .clipShape(Capsule())
        .shadow(radius: 8)
        .buttonStyle(.plain)
        .help("执行切断并自动恢复")
        .onHover { isHovered = $0 }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var buttonColor: Color {
        if model.oneKeyButtonIsPressed { return .gray }
        if !model.isMonitoring {
            return isHovered ? Color.red.opacity(0.82) : .red
        }
        if model.canTriggerOneKeyAction {
            return isHovered ? Color.green.opacity(0.78) : .green
        }
        return isHovered ? Color.orange.opacity(0.82) : .orange
    }
}

enum ModelEditError: LocalizedError {
    case invalidTopLevelObject
    case rulesArrayNotFound

    var errorDescription: String? {
        switch self {
        case .invalidTopLevelObject:
            return "导出的 Little Snitch 模型不是预期的 JSON 对象。"
        case .rulesArrayNotFound:
            return "导出的 Little Snitch 模型中未找到 rules 数组。"
        }
    }
}

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "未找到 Keychain 项目"
        case .unexpectedData:
            return "Keychain 返回了无法识别的数据"
        case .unhandledStatus(let status):
            return "Keychain 错误，状态码：\(status)"
        }
    }
}

enum KeychainHelper {
    static func save(service: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status != errSecItemNotFound {
            throw KeychainError.unhandledStatus(status)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    static func read(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func exists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
