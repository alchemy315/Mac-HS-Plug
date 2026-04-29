import SwiftUI
import KeyboardShortcuts
import AppKit

private enum SidebarTab: String, CaseIterable, Identifiable {
    case disconnect = "拔线"
    case settings = "拔线设置"
    case system = "系统设置"
    case logs = "日志"
    case tutorial = "教程"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .disconnect: return "bolt.fill"
        case .settings: return "slider.horizontal.3"
        case .system: return "gearshape.fill"
        case .logs: return "doc.text.fill"
        case .tutorial: return "book.fill"
        case .about: return "info.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .disconnect: return "监控、点击、悬浮窗、快捷键"
        case .settings: return "启动与拔线参数"
        case .system: return "路径、密码与权限"
        case .logs: return "统计与运行日志"
        case .tutorial: return "大致使用流程说明"
        case .about: return "版本与作者信息"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showResetConfirmation = false
    @State private var selectedTab: SidebarTab = .disconnect
    @State private var highlightedCardKey: String? = nil

    private let appDisplayName = "一键拔线"
    private let appSubtitle = "Little Snitch 辅助工具"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.2)
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            model.handleAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            model.refreshCurrentShortcutText()
        }
        .alert("确认还原", isPresented: $showResetConfirmation) {
            Button("取消", role: .cancel) { }
            Button("还原", role: .destructive) {
                model.resetToInitialState()
            }
        } message: {
            Text("这会清除已保存的密码、路径、日志、统计和当前设置，并恢复到初始状态。")
        }
    }

    private func navigateAndHighlight(tab: SidebarTab, cardKey: String) {
        selectedTab = tab
        highlightedCardKey = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.2)) {
                highlightedCardKey = cardKey
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    highlightedCardKey = nil
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    highlightedCardKey = cardKey
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    highlightedCardKey = nil
                }
            }
        }
    }

    private func isHighlighted(_ key: String) -> Bool {
        highlightedCardKey == key
    }


    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        sidebarBrandIcon

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appDisplayName)
                                .font(.headline)
                            Text(appSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    ForEach(SidebarTab.allCases) { tab in
                        SidebarButton(tab: tab, isSelected: selectedTab == tab) {
                            selectedTab = tab
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 8)

            UnifiedFooterStatusRow(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 200, alignment: .topLeading)
        .background(Color.black.opacity(0.03))
    }

    private var sidebarBrandIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let image = NSImage(named: "SidebarLogo") ?? Bundle.main.image(forResource: "SidebarLogo") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            } else {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 44, height: 44)
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader
                switch selectedTab {
                case .disconnect:
                    disconnectPage
                case .settings:
                    settingsPage
                case .system:
                    systemPage
                case .logs:
                    logsPage
                case .tutorial:
                    tutorialPage
                case .about:
                    aboutPage
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedTab.rawValue)
                .font(.system(size: 26, weight: .bold))
            Text(selectedTab.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var disconnectPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardCard(title: "监控控制", systemImage: "waveform.path.ecg", isHighlighted: isHighlighted("monitoring")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("开启对局监控")
                            .font(.subheadline)
                        Toggle("", isOn: Binding(
                            get: { model.isMonitoring },
                            set: { enabled in
                                model.toggleMonitoringFromMenuBar(enabled)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Text(model.monitoringToggleStatusText)
                        .font(.caption)
                        .foregroundStyle(model.monitoringToggleStatusColor)
                }
            }

            DashboardCard(title: "点击拔线", systemImage: "bolt.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        model.triggerOneKeyAction(triggerSource: "button")
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                            Text("一键拔线")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(model.oneKeyButtonIsPressed ? Color.gray : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canTriggerOneKeyAction)
                    .animation(.easeInOut(duration: 0.2), value: model.oneKeyButtonIsPressed)

                    if !model.isMonitoring {
                        Text("未开启监控")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !model.canTriggerOneKeyAction {
                        Text("未检测到对局IP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DashboardCard(title: "悬浮窗拔线", systemImage: "rectangle.on.rectangle.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("开启悬浮窗拔线", isOn: $model.enableFloatingButton)
                        .toggleStyle(.switch)
                    if model.enableFloatingButton {
                        (
                            Text("已启动悬浮窗，").foregroundColor(.green)
                            + Text("红色按钮").foregroundColor(.red)
                            + Text("表示未开启检测，")
                            + Text("黄色按钮").foregroundColor(.orange)
                            + Text("表示未检测到对局，")
                            + Text("绿色按钮").foregroundColor(.green)
                            + Text("表示已检测到对局")
                        )
                        .font(.caption)
                    } else {
                        Text("关闭后将不再显示始终置顶的一键拔线悬浮按钮。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DashboardCard(title: "快捷键拔线", systemImage: "keyboard.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("开启快捷键拔线", isOn: $model.enableHotKeyTrigger)
                        .toggleStyle(.switch)
                    HStack(spacing: 10) {
                        Text("全局快捷键：")
                            .font(.subheadline)
                        KeyboardShortcuts.Recorder("", name: .timedBlockRestore)
                            .labelsHidden()
                            .disabled(!model.enableHotKeyTrigger)
                    }
                    Text(model.hotKeyStatusText)
                        .font(.caption)
                        .foregroundStyle(model.hotKeyStatusColor)
                }
            }

            DashboardCard(title: "菜单栏拔线", systemImage: "menubar.rectangle") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("开启菜单栏拔线", isOn: $model.enableMenuBarControl)
                        .toggleStyle(.switch)
                    Text(model.enableMenuBarControl ? "已开启。右上角菜单栏会显示一个小图标，可直接进行监控与一键拔线。" : "关闭后将不再在菜单栏显示该软件图标。")
                        .font(.caption)
                        .foregroundStyle(model.enableMenuBarControl ? .green : .secondary)
                }
            }
        }
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardCard(title: "启动设置", systemImage: "power") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("打开软件时自动开始监控", isOn: $model.autoStartMonitoring)
                        .toggleStyle(.switch)
                    Text(model.autoStartMonitoring ? "已开启。下次打开软件时会自动尝试开始监控，并先进行一次权限确认。" : "未开启自动开始监控。")
                        .font(.caption)
                        .foregroundStyle(model.autoStartMonitoring ? .green : .secondary)

                    Toggle("监控时申请后台活动", isOn: $model.enableBackgroundActivity)
                        .toggleStyle(.switch)
                    Text(model.enableBackgroundActivity ? "已开启。监控运行时会申请后台活动，减少被系统挂起的可能。" : "未开启后台活动申请。")
                        .font(.caption)
                        .foregroundStyle(model.enableBackgroundActivity ? .green : .secondary)
                }
            }

            DashboardCard(title: "候选 IP 与拔线间隔", systemImage: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("精准控制", isOn: $model.filterBattleIPsOnly)
                            .toggleStyle(.switch)
                        Text(model.filterBattleHintText)
                            .font(.caption)
                            .foregroundStyle(model.filterBattleHintColor)
                    }

                    settingRow(title: "控制连接数：") {
                        TextField("1", text: $model.activeCandidateLimitText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .disabled(!model.isCandidateLimitEnabled)
                        Text(model.currentCandidateLimitStatusText)
                            .font(.caption)
                            .foregroundStyle(model.currentCandidateLimitStatusColor)
                    }
                    .foregroundStyle(model.isCandidateLimitEnabled ? Color.primary : Color.secondary)

                    settingRow(title: "拔线间隔秒数：") {
                        TextField("例如 0.1", text: $model.autoRestoreSecondsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text(model.currentIntervalStatusText)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var systemPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardCard(title: "路径设置", systemImage: "folder.fill", isHighlighted: isHighlighted("paths")) {
                VStack(alignment: .leading, spacing: 12) {
                    pathRow(
                        title: "Little Snitch 路径：",
                        placeholder: "路径可能为 /Applications/Little Snitch.app",
                        text: $model.executablePath,
                        statusText: model.littleSnitchPathTestStatusText,
                        statusColor: model.littleSnitchPathTestColor,
                        browseAction: model.browseExecutablePath,
                        testAction: model.testExecutablePath
                    )

                    pathRow(
                        title: "炉石传说路径：",
                        placeholder: "路径可能为 /Applications/Hearthstone/Hearthstone.app",
                        text: $model.targetPath,
                        statusText: model.targetPathTestStatusText,
                        statusColor: model.targetPathTestColor,
                        browseAction: model.browseTargetPath,
                        testAction: model.testTargetPath
                    )
                }
            }

            DashboardCard(title: "sudo / Keychain / 权限确认", systemImage: "lock.shield.fill", isHighlighted: isHighlighted("password")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        SecureField("输入sudo密码", text: $model.passwordInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .onTapGesture {
                                model.beginPasswordEditing()
                            }
                        Button("保存密码", action: model.savePasswordToKeychain)
                        Button("删除密码", action: model.deletePasswordFromKeychain)
                        Button("确认权限", action: model.confirmPermissions)
                    }

                    Text("将密码存储到Keychain以保证程序静默启动监控，在弹出权限请求时需要点击“始终允许”")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(model.systemPasswordFeedbackText)
                        .font(.caption)
                        .foregroundStyle(model.systemPasswordFeedbackColor)
                }
            }
        }
    }

    private var logsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardCard(title: "运行概览", systemImage: "chart.bar.fill") {
                statsGrid
            }

            VStack(alignment: .leading, spacing: 14) {
                connectionStatsCard
                runLogsCard
            }
        }
    }

    private var tutorialPage: some View {
        DashboardCard(title: "使用流程", systemImage: "book.fill") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text("1. 打开 Little Snitch，点击左上角菜单栏 Little Snitch -> Settings -> Security -> 勾选 Allow access via Terminal 以打开命令行权限")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                tutorialNavigateRow(number: 2, text: "设置Little Snitch和炉石传说的路径", target: .system, cardKey: "paths")
                tutorialNavigateRow(number: 3, text: "保存sudo密码并确认权限", target: .system, cardKey: "password")
                tutorialNavigateRow(number: 4, text: "开启监控并选择拔线方式", target: .disconnect, cardKey: "monitoring")
            }
        }
    }

    @ViewBuilder
    private func tutorialNavigateRow(number: Int, text: String, target: SidebarTab, cardKey: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number). \(text)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("前往") {
                navigateAndHighlight(tab: target, cardKey: cardKey)
            }
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardCard(title: "关于", systemImage: "info.circle.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("版本：1.0", systemImage: "shippingbox.fill")
                        Label("作者：alchemy & ai", systemImage: "person.2.fill")
                        
                        // ===== 添加的 GitHub 链接 =====
                        // 请在此处将 https://github.com/your-username/your-repo 替换为你真实的仓库地址
                        Link(destination: URL(string: "https://github.com/alchemy315/Mac-HS-Plug")!) {
                            Label("源代码：GitHub", systemImage: "link")
                        }
                    }
                    .font(.body)

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("还原为初始状态", systemImage: "arrow.counterclockwise.circle")
                    }
                }
            }
        }
    }

    private var connectionStatsCard: some View {
        DashboardCard(title: "连接统计", systemImage: "list.bullet.rectangle.portrait") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("清空统计", action: model.clearStats)
                    Spacer(minLength: 0)
                }
                if model.displayedEndpointStats.isEmpty {
                    Text("点击“开始监控”后，这里会显示目标地址、命中次数、方向、端口和协议。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                } else {
                    List(model.displayedEndpointStats) { item in
                        EndpointRow(item: item)
                    }
                    .frame(height: 160)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var runLogsCard: some View {
        DashboardCard(title: "运行日志", systemImage: "terminal.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("清空日志", action: model.clearLogs)
                    Spacer(minLength: 0)
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        if model.logs.isEmpty {
                            Text("暂无日志")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.logs) { log in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("[\(log.time)] ")
                                            .foregroundStyle(log.type.color)
                                        + Text(log.message)
                                            .foregroundStyle(Color.primary)
                                        
                                        if let raw = log.rawOutput, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text("--------\n\(raw.trimmingCharacters(in: .whitespacesAndNewlines))\n--------")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .id(log.id)
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                        }
                    }
                    .frame(height: 220)
                    .onChange(of: model.logs.count) {
                        if let lastLog = model.logs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsGrid: some View {
        let spacing: CGFloat = 12
        let columns = [
            GridItem(.adaptive(minimum: 112, maximum: 140), spacing: spacing, alignment: .leading)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            StatBadge(title: "目标种类", value: "\(model.uniqueEndpointCount)")
            StatBadge(title: "总命中", value: "\(model.totalHitCount)")
            StatBadge(title: "出站", value: "\(model.totalOutboundCount)")
            StatBadge(title: "入站", value: "\(model.totalInboundCount)")
            StatBadge(title: "已切断 IP", value: "\(model.blockedIPCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .frame(width: 125, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func pathRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        statusText: String,
        statusColor: Color,
        browseAction: @escaping () -> Void,
        testAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .frame(width: 125, alignment: .leading)
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("浏览...", action: browseAction)
                Button("测试路径", action: testAction)
            }
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .padding(.leading, 155)
            }
        }
    }
}

private struct SidebarButton: View {
    let tab: SidebarTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.rawValue)
                        .font(.headline)
                    Text(tab.subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.green : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let isHighlighted: Bool
    @ViewBuilder var content: Content

    init(title: String, systemImage: String, isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isHighlighted ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.05), lineWidth: isHighlighted ? 2 : 1)
        )
        .shadow(color: isHighlighted ? Color.accentColor.opacity(0.18) : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
    }
}

private struct TutorialRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.green)
                .clipShape(Circle())
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EndpointRow: View {
    let item: EndpointAggregate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.endpoint)
                    .font(.system(.body, design: .monospaced))
                Text(item.hasURL ? "有 URL" : "无 URL（对局候选）")
                    .font(.caption)
                    .foregroundStyle(item.hasURL ? Color.secondary : Color.orange)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("命中 \(item.hitCount)")
                Text("出 \(item.outboundCount) / 入 \(item.inboundCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.protocols.sorted().joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(item.ports.sorted().map(String.init).joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct StatBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 90)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
