//
//  ContentView.swift
//  SSHocks
//
//  Created by JIANGJINGZHE on 17/6/2026.
//

import AppKit
import SwiftUI

enum AuthMethod: String, CaseIterable, Identifiable, Codable {
    case password
    case privateKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password:
            return "密码"
        case .privateKey:
            return "私钥"
        }
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case overview
    case connect
    case profiles
    case clash
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "总览"
        case .connect:
            return "新建连接"
        case .profiles:
            return "服务器池"
        case .clash:
            return "Clash 配置"
        case .diagnostics:
            return "诊断"
        case .settings:
            return "偏好设置"
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            return "speedometer"
        case .connect:
            return "plus.circle"
        case .profiles:
            return "server.rack"
        case .clash:
            return "curlybraces.square"
        case .diagnostics:
            return "waveform.path.ecg"
        case .settings:
            return "gearshape"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "状态与快捷操作"
        case .connect:
            return "添加 SSH 出口"
        case .profiles:
            return "已鉴权服务器"
        case .clash:
            return "生成 YAML 片段"
        case .diagnostics:
            return "端口与连通性"
        case .settings:
            return "默认值与行为"
        }
    }

    static let groupedTabs: [(title: String, tabs: [SidebarTab])] = [
        ("代理", [.overview, .connect, .profiles]),
        ("工具", [.clash, .diagnostics]),
        ("管理", [.settings])
    ]
}

struct SSHProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var localPort: Int
    var proxyName: String
    var authMethod: AuthMethod
    var privateKeyPath: String
    var verifiedAt: Date
    var lastConnectedAt: Date
    var connectionCount: Int
    var groupName: String
    var tags: [String]
    var isFavorite: Bool

    var keychainAccount: String {
        id.uuidString
    }

    var endpointKey: String {
        "\(username.lowercased())@\(host.lowercased()):\(sshPort):\(authMethod.rawValue)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        sshPort: Int,
        username: String,
        localPort: Int,
        proxyName: String,
        authMethod: AuthMethod,
        privateKeyPath: String,
        verifiedAt: Date = Date(),
        lastConnectedAt: Date = Date(),
        connectionCount: Int = 1,
        groupName: String = "默认",
        tags: [String] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.sshPort = sshPort
        self.username = username
        self.localPort = localPort
        self.proxyName = proxyName
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.verifiedAt = verifiedAt
        self.lastConnectedAt = lastConnectedAt
        self.connectionCount = connectionCount
        self.groupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "默认"
            : groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.isFavorite = isFavorite
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case sshPort
        case username
        case localPort
        case proxyName
        case authMethod
        case privateKeyPath
        case verifiedAt
        case lastConnectedAt
        case connectionCount
        case groupName
        case tags
        case isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        sshPort = try container.decode(Int.self, forKey: .sshPort)
        username = try container.decode(String.self, forKey: .username)
        localPort = try container.decode(Int.self, forKey: .localPort)
        proxyName = try container.decode(String.self, forKey: .proxyName)
        authMethod = try container.decode(AuthMethod.self, forKey: .authMethod)
        privateKeyPath = try container.decode(String.self, forKey: .privateKeyPath)
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt) ?? Date()
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt) ?? verifiedAt
        connectionCount = try container.decodeIfPresent(Int.self, forKey: .connectionCount) ?? 1
        let decodedGroup = try container.decodeIfPresent(String.self, forKey: .groupName) ?? "默认"
        groupName = decodedGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "默认"
            : decodedGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

enum ProfileSortOption: String, CaseIterable, Identifiable {
    case favorite
    case recent
    case name
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorite:
            return "收藏优先"
        case .recent:
            return "最近连接"
        case .name:
            return "名称"
        case .group:
            return "分组"
        }
    }
}

enum SSHProfileStore {
    private static let key = "sshProfiles"

    static func load() -> [SSHProfile] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let profiles = try? JSONDecoder().decode([SSHProfile].self, from: data)
        else {
            return []
        }

        return profiles
    }

    static func save(_ profiles: [SSHProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum SSHocksVisual {
    static let pageMaxWidth: CGFloat = 1_160
    static let primaryColumnWidth: CGFloat = 470
    static let sideColumnWidth: CGFloat = 520
    static let compactColumnWidth: CGFloat = 360
    static let pagePadding: CGFloat = 28
    static let columnSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 10
}

private struct SSHocksPanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(SSHocksVisual.cardPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SSHocksVisual.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SSHocksVisual.cardRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.7)
            }
    }
}

private extension View {
    func sshocksPanelCard() -> some View {
        modifier(SSHocksPanelCard())
    }

    func sshocksPrimaryColumn() -> some View {
        frame(
            minWidth: SSHocksVisual.compactColumnWidth,
            idealWidth: SSHocksVisual.primaryColumnWidth,
            maxWidth: SSHocksVisual.primaryColumnWidth,
            alignment: .topLeading
        )
    }

    func sshocksSideColumn() -> some View {
        frame(
            minWidth: SSHocksVisual.compactColumnWidth,
            idealWidth: SSHocksVisual.sideColumnWidth,
            maxWidth: .infinity,
            alignment: .topLeading
        )
    }
}

struct SSHProfileDraft: Identifiable {
    var id: UUID
    var isNew: Bool
    var name: String
    var host: String
    var sshPort: Int
    var username: String
    var localPort: Int
    var proxyName: String
    var authMethod: AuthMethod
    var privateKeyPath: String
    var password: String
    var verifiedAt: Date
    var lastConnectedAt: Date
    var connectionCount: Int
    var groupName: String
    var tagsText: String
    var isFavorite: Bool

    init(profile: SSHProfile? = nil) {
        if let profile {
            id = profile.id
            isNew = false
            name = profile.name
            host = profile.host
            sshPort = profile.sshPort
            username = profile.username
            localPort = profile.localPort
            proxyName = profile.proxyName
            authMethod = profile.authMethod
            privateKeyPath = profile.privateKeyPath
            password = KeychainStore.password(account: profile.keychainAccount) ?? ""
            verifiedAt = profile.verifiedAt
            lastConnectedAt = profile.lastConnectedAt
            connectionCount = profile.connectionCount
            groupName = profile.groupName
            tagsText = profile.tags.joined(separator: ", ")
            isFavorite = profile.isFavorite
        } else {
            id = UUID()
            isNew = true
            name = ""
            host = ""
            sshPort = 22
            username = ""
            localPort = 1080
            proxyName = "SSH SOCKS"
            authMethod = .password
            privateKeyPath = ""
            password = ""
            verifiedAt = Date()
            lastConnectedAt = Date()
            connectionCount = 0
            groupName = "默认"
            tagsText = ""
            isFavorite = false
        }
    }

    var profile: SSHProfile {
        let parsedTags = tagsText
            .split { character in
                character == "," || character == "，" || character == " " || character == "\n"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return SSHProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            sshPort: sshPort,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            localPort: localPort,
            proxyName: proxyName.trimmingCharacters(in: .whitespacesAndNewlines),
            authMethod: authMethod,
            privateKeyPath: privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines),
            verifiedAt: verifiedAt,
            lastConnectedAt: lastConnectedAt,
            connectionCount: connectionCount,
            groupName: groupName,
            tags: parsedTags,
            isFavorite: isFavorite
        )
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...65535).contains(sshPort)
            && (1...65535).contains(localPort)
            && (authMethod == .password || !privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && (authMethod == .privateKey || !password.isEmpty)
    }
}

struct SSHProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SSHProfileDraft

    var onSave: (SSHProfileDraft) -> Void

    init(draft: SSHProfileDraft, onSave: @escaping (SSHProfileDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.isNew ? "新增服务器" : "编辑服务器")
                        .font(.title2.weight(.semibold))
                    Text("服务器池条目保存连接元数据，密码会写入 macOS Keychain。")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding([.horizontal, .top], 22)
            .padding(.bottom, 12)

            Form {
                Section("基本信息") {
                    TextField("名称", text: $draft.name)
                    TextField("服务器地址或域名", text: $draft.host)
                    TextField("用户名", text: $draft.username)
                    TextField("SSH 端口", value: $draft.sshPort, format: .number)
                }

                Section("访问鉴权") {
                    Picker("方式", selection: $draft.authMethod) {
                        ForEach(AuthMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.authMethod == .password {
                        SecureField("SSH 密码", text: $draft.password)
                            .textContentType(.password)
                    } else {
                        HStack {
                            TextField("私钥路径", text: $draft.privateKeyPath)
                            Button {
                                choosePrivateKey()
                            } label: {
                                Label("选择", systemImage: "folder")
                            }
                        }
                    }
                }

                Section("本地代理") {
                    TextField("本地 SOCKS5 端口", value: $draft.localPort, format: .number)
                    TextField("Clash 节点名称", text: $draft.proxyName)
                }

                Section("整理") {
                    TextField("分组", text: $draft.groupName)
                    TextField("标签，用逗号或空格分隔", text: $draft.tagsText)
                    Toggle("收藏", isOn: $draft.isFavorite)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消") {
                    dismiss()
                }

                Spacer()

                Button {
                    onSave(draft)
                    dismiss()
                } label: {
                    Label(draft.isNew ? "新增" : "保存", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
            .padding(16)
        }
        .frame(width: 520, height: 640)
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.title = "选择 SSH 私钥"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            draft.privateKeyPath = url.path
        }
    }
}

struct ContentView: View {
    @ObservedObject var tunnelManager: SSHTunnelManager
    @ObservedObject var systemProxyManager: SystemProxyManager
    @ObservedObject var healthMonitor: ProxyHealthMonitor
    @ObservedObject var tunModeManager: TUNModeManager

    @AppStorage("sshHost") private var sshHost = ""
    @AppStorage("sshPort") private var sshPort = 22
    @AppStorage("sshUsername") private var sshUsername = ""
    @AppStorage("privateKeyPath") private var privateKeyPath = ""
    @AppStorage("localPort") private var localPort = 1080
    @AppStorage("proxyName") private var proxyName = "Termius SSH SOCKS"
    @AppStorage("authMethod") private var authMethodRawValue = AuthMethod.password.rawValue
    @AppStorage("proxiedDomains") private var proxiedDomains = "google.com\nyoutube.com"
    @AppStorage("directChinaTraffic") private var directChinaTraffic = true
    @AppStorage("matchProxy") private var matchProxy = true
    @AppStorage("autoCopyProxyAddress") private var autoCopyProxyAddress = false
    @AppStorage("selectedNetworkService") private var selectedNetworkService = ""
    @AppStorage("autoEnableSystemProxy") private var autoEnableSystemProxy = false
    @AppStorage("autoDisableSystemProxy") private var autoDisableSystemProxy = true
    @AppStorage("autoReconnectEnabled") private var autoReconnectEnabled = true
    @AppStorage("healthCheckEnabled") private var healthCheckEnabled = true
    @AppStorage("tunModeEnabled") private var tunModeEnabled = false

    @State private var selectedTab: SidebarTab = .overview
    @State private var sshPassword = ""
    @State private var copiedClashYAML = false
    @State private var copiedProxyAddress = false
    @State private var profiles = SSHProfileStore.load()
    @State private var profileName = ""
    @State private var profileEditorDraft: SSHProfileDraft?
    @State private var serverPoolMessage = "连接鉴权成功后，服务器会自动加入这里。"
    @State private var diagnosticsLog = "点击“运行诊断”检查本机 ssh、端口占用和当前代理可达性。"
    @State private var isRunningDiagnostics = false
    @State private var connectionDraftHydrated = false
    @State private var draftSSHHost = ""
    @State private var draftSSHPort = 22
    @State private var draftSSHUsername = ""
    @State private var draftPrivateKeyPath = ""
    @State private var draftLocalPort = 1080
    @State private var draftProxyName = "Termius SSH SOCKS"
    @State private var draftAuthMethod = AuthMethod.password
    @State private var profileSearchInput = ""
    @State private var profileSearchText = ""
    @State private var profileSearchDebounceTask: Task<Void, Never>?
    @State private var profileSortOption: ProfileSortOption = .favorite

    private var authMethod: Binding<AuthMethod> {
        Binding {
            AuthMethod(rawValue: authMethodRawValue) ?? .password
        } set: { newValue in
            authMethodRawValue = newValue.rawValue
        }
    }

    private var draftAuthMethodBinding: Binding<AuthMethod> {
        Binding {
            draftAuthMethod
        } set: { newValue in
            draftAuthMethod = newValue
        }
    }

    private var proxyAddress: String {
        "socks5://127.0.0.1:\(localPort)"
    }

    private var connectionProxyAddress: String {
        "socks5://127.0.0.1:\(draftLocalPort)"
    }

    private var activeNetworkService: String {
        if !selectedNetworkService.isEmpty {
            return selectedNetworkService
        }
        return systemProxyManager.services.first ?? "Wi-Fi"
    }

    private var recentProfiles: [SSHProfile] {
        Array(profiles.prefix(3))
    }

    private var sortedProfiles: [SSHProfile] {
        profiles.sorted { lhs, rhs in
            switch profileSortOption {
            case .favorite:
                if lhs.isFavorite != rhs.isFavorite {
                    return lhs.isFavorite && !rhs.isFavorite
                }
                return lhs.lastConnectedAt > rhs.lastConnectedAt
            case .recent:
                return lhs.lastConnectedAt > rhs.lastConnectedAt
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .group:
                let groupCompare = lhs.groupName.localizedStandardCompare(rhs.groupName)
                if groupCompare != .orderedSame {
                    return groupCompare == .orderedAscending
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var filteredProfiles: [SSHProfile] {
        let query = profileSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedProfiles }

        return sortedProfiles.filter { profile in
            [
                profile.name,
                profile.host,
                profile.username,
                profile.groupName,
                profile.tags.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var groupedFilteredProfiles: [(name: String, profiles: [SSHProfile])] {
        let dictionary = Dictionary(grouping: filteredProfiles, by: \.groupName)
        return dictionary.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { groupName in
                (groupName, dictionary[groupName] ?? [])
            }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            selectedDetail
        }
        .frame(minWidth: 760, minHeight: 560)
        .task {
            hydrateConnectionDraftIfNeeded()
            await loadNetworkServicesIfNeeded()
            tunModeManager.refreshAvailability()
        }
        .onChange(of: tunnelManager.state) { oldState, newState in
            if newState == .connected {
                rememberAuthenticatedServer()
                if healthCheckEnabled {
                    healthMonitor.start(port: localPort)
                }
                if autoEnableSystemProxy {
                    enableSystemProxy()
                }
                if tunModeEnabled {
                    enableTUNMode()
                }
            } else if oldState == .connected {
                healthMonitor.stop()
                let isAutoReconnecting: Bool = {
                    if case .connecting = newState {
                        return tunnelManager.reconnectAttempt > 0
                    }
                    return false
                }()
                if autoDisableSystemProxy, !isAutoReconnecting {
                    disableSystemProxy()
                }
                if tunModeEnabled, !isAutoReconnecting {
                    disableTUNMode()
                }
            } else if autoDisableSystemProxy {
                if case .failed = newState {
                    disableSystemProxy()
                }
            }

            if case .failed = newState {
                disableTUNMode()
            }
        }
        .onChange(of: healthCheckEnabled) { _, enabled in
            if enabled, tunnelManager.state == .connected {
                healthMonitor.start(port: localPort)
            } else if !enabled {
                healthMonitor.stop()
            }
        }
        .onChange(of: selectedNetworkService) { _, _ in
            Task {
                await systemProxyManager.refresh(service: activeNetworkService)
            }
        }
        .onChange(of: profileSearchInput) { _, newValue in
            profileSearchDebounceTask?.cancel()
            profileSearchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                profileSearchText = newValue
            }
        }
        .sheet(item: $profileEditorDraft) { draft in
            SSHProfileEditorView(draft: draft) { updatedDraft in
                upsertProfile(updatedDraft)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SidebarTab.groupedTabs, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.tabs) { tab in
                        sidebarRow(for: tab)
                            .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SSHocks")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .safeAreaInset(edge: .bottom) {
            sidebarStatus
                .padding(12)
        }
    }

    private func sidebarRow(for tab: SidebarTab) -> some View {
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title)
                        .lineLimit(1)
                    Text(tab.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                sidebarBadge(for: tab)
            }
        } icon: {
            Image(systemName: tab.symbol)
        }
    }

    @ViewBuilder
    private func sidebarBadge(for tab: SidebarTab) -> some View {
        switch tab {
        case .profiles where !profiles.isEmpty:
            Text("\(profiles.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        case .diagnostics where isRunningDiagnostics:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
        case .overview where tunnelManager.isRunning:
            Circle()
                .fill(tunnelManager.state == .connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
        default:
            EmptyView()
        }
    }

    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusBadge
            Text("127.0.0.1:\(localPort)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .connect:
            connectTab
        case .clash:
            clashTab
        case .diagnostics:
            diagnosticsTab
        case .profiles:
            profilesTab
        case .settings:
            settingsTab
        }
    }

    private var overviewTab: some View {
        detailContainer(title: "总览", subtitle: "查看当前 SOCKS5 隧道状态，并从服务器池快速启动常用出口。") {
            VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: SSHocksVisual.columnSpacing) {
                        overviewStatusPanel
                        overviewActionsPanel
                    }

                    VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
                        overviewStatusPanel
                        overviewActionsPanel
                    }
                }

                recentServersPanel
            }
        }
    }

    private var connectTab: some View {
        detailContainer(title: "连接", subtitle: "填入 SSH 凭证后，在本地回环地址启动 SOCKS5 代理。") {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: SSHocksVisual.compactColumnWidth, maximum: SSHocksVisual.sideColumnWidth), spacing: SSHocksVisual.columnSpacing, alignment: .top)
                ],
                alignment: .leading,
                spacing: SSHocksVisual.sectionSpacing
            ) {
                connectionForm
                connectionSidePanel
            }
        }
    }

    private var clashTab: some View {
        detailContainer(title: "Clash", subtitle: "生成可粘贴到 ClashX Pro 配置里的 SOCKS5 节点、策略组和规则。") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SSHocksVisual.columnSpacing) {
                    clashForm
                    clashPanel
                }

                VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
                    clashForm
                    clashPanel
                }
            }
        }
    }

    private var diagnosticsTab: some View {
        detailContainer(title: "诊断", subtitle: "快速定位连接失败、端口占用和 SOCKS5 可达性问题。") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        runDiagnostics()
                    } label: {
                        Label(isRunningDiagnostics ? "诊断中" : "运行诊断", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunningDiagnostics)

                    Button {
                        copy(diagnosticsLog)
                    } label: {
                        Label("复制结果", systemImage: "doc.on.doc")
                    }

                    Spacer()
                }

                ScrollView {
                    Text(diagnosticsLog)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .frame(minHeight: 260)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.7)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        diagnosticHints
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        diagnosticHints
                    }
                }
            }
        }
    }

    private var profilesTab: some View {
        detailContainer(title: "服务器池", subtitle: "保存已经鉴权成功的服务器，之后可以快速选择并启动连接。") {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: SSHocksVisual.compactColumnWidth, maximum: SSHocksVisual.sideColumnWidth), spacing: SSHocksVisual.columnSpacing, alignment: .top)
                ],
                alignment: .leading,
                spacing: SSHocksVisual.sectionSpacing
            ) {
                profileListPanel
                profileInfoPanel
            }
        }
    }

    private var settingsTab: some View {
        detailContainer(title: "偏好设置", subtitle: "控制默认行为和常用出口信息。") {
            VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    panelHeader("连接默认值", systemImage: "slider.horizontal.3")

                    VStack(spacing: 0) {
                        formRow("SSH 端口") {
                            TextField("22", value: $sshPort, format: .number)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                                .frame(width: 96)
                        }

                        Divider()

                        formRow("SOCKS5 端口") {
                            TextField("1080", value: $localPort, format: .number)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                                .frame(width: 96)
                        }

                        Divider()

                        formRow("节点名称") {
                            TextField("Termius SSH SOCKS", text: $proxyName)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                        }
                    }
                }
                .sshocksPanelCard()

                VStack(alignment: .leading, spacing: 10) {
                    panelHeader("行为", systemImage: "slider.horizontal.3")

                    toggleRow("连接成功后自动复制 SOCKS5 地址", isOn: $autoCopyProxyAddress)
                    toggleRow("连接意外断开后自动重连", isOn: $autoReconnectEnabled)
                    toggleRow("连接后持续检测 SOCKS5 健康状态", isOn: $healthCheckEnabled)
                    toggleRow("Clash 规则默认国内直连", isOn: $directChinaTraffic)
                    toggleRow("Clash 规则默认未命中走代理", isOn: $matchProxy)
                }
                .sshocksPanelCard()

                VStack(alignment: .leading, spacing: 12) {
                    panelHeader("系统代理", systemImage: "network")

                    if systemProxyManager.services.isEmpty {
                        Text("尚未读取网络服务。")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("网络服务", selection: $selectedNetworkService) {
                            ForEach(systemProxyManager.services, id: \.self) { service in
                                Text(service).tag(service)
                            }
                        }
                    }

                    toggleRow("连接成功后自动开启系统代理", isOn: $autoEnableSystemProxy)
                    toggleRow("断开连接后自动关闭系统代理", isOn: $autoDisableSystemProxy)

                    HStack {
                        Text(proxyAddress)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            copy(proxyAddress)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }

                    HStack {
                        Button {
                            refreshSystemProxy()
                        } label: {
                            Label("刷新服务", systemImage: "arrow.clockwise")
                        }
                        .disabled(systemProxyManager.isWorking)

                        Button {
                            enableSystemProxy()
                        } label: {
                            Label("开启系统代理", systemImage: "network")
                        }
                        .disabled(systemProxyManager.isWorking)

                        Button {
                            disableSystemProxy()
                        } label: {
                            Label("关闭系统代理", systemImage: "xmark.circle")
                        }
                        .disabled(systemProxyManager.isWorking)
                    }

                    Text(systemProxyManager.detail)
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Network.prefPane"))
                    } label: {
                        Label("打开网络设置", systemImage: "network")
                    }
                }
                .sshocksPanelCard()

                VStack(alignment: .leading, spacing: 12) {
                    panelHeader("TUN 模式", systemImage: "network")

                    toggleRow("启用 TUN 模式", isOn: Binding {
                        tunModeEnabled
                    } set: { enabled in
                        tunModeEnabled = enabled
                        if enabled {
                            enableTUNMode()
                        } else {
                            disableTUNMode()
                        }
                    })

                    HStack(spacing: 12) {
                        Label(tunModeManager.state.title, systemImage: tunModeManager.state.symbol)
                            .foregroundStyle(tunModeManager.isEnabled ? .green : .secondary)

                        Button {
                            tunModeManager.refreshAvailability()
                        } label: {
                            Label("检测引擎", systemImage: "magnifyingglass")
                        }
                        .disabled(tunModeManager.isInstallingPackage)

                        Button {
                            installTUNPackage()
                        } label: {
                            Label(
                                tunModeManager.isInstallingPackage ? "安装中" : "安装套件",
                                systemImage: "shippingbox"
                            )
                        }
                        .disabled(tunModeManager.isInstallingPackage)

                        Button {
                            tunModeEnabled = true
                            enableTUNMode()
                        } label: {
                            Label("开启", systemImage: "power")
                        }
                        .disabled(tunModeManager.isEnabled || tunModeManager.isInstallingPackage)

                        Button {
                            tunModeEnabled = false
                            disableTUNMode()
                        } label: {
                            Label("关闭", systemImage: "xmark.circle")
                        }
                    }

                    Text(tunModeManager.detail)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Text("TUN 模式会尝试通过本机 TUN 引擎把系统路由导向 127.0.0.1:\(localPort) 的 SOCKS5 出口。macOS 上通常需要 sing-box 可执行文件和相应网络权限。")
                        .foregroundStyle(.secondary)
                }
                .sshocksPanelCard()
            }
            .frame(minWidth: SSHocksVisual.compactColumnWidth, maxWidth: 680, alignment: .leading)
        }
    }

    private var connectionForm: some View {
        VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
            sshSection
            authSection
            localProxySection
        }
        .sshocksPrimaryColumn()
    }

    private var connectionSidePanel: some View {
        VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
            statusPanel
            quickActionsPanel
            logPanel
        }
        .sshocksSideColumn()
    }

    private var overviewStatusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("当前隧道", systemImage: "network")

            statusBadge

            Text(tunnelManager.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                Text(connectionProxyAddress)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    copy(proxyAddress)
                    copiedProxyAddress = true
                } label: {
                    Label(copiedProxyAddress ? "已复制" : "复制", systemImage: "doc.on.doc")
                }
            }
        }
        .sshocksPanelCard()
        .sshocksSideColumn()
    }

    private var overviewActionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("快捷任务", systemImage: "bolt.circle")

            Button {
                selectedTab = .connect
            } label: {
                Label("添加 SSH 服务器", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                selectedTab = .profiles
            } label: {
                Label("打开服务器池", systemImage: "server.rack")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                selectedTab = .clash
            } label: {
                Label("生成 Clash 配置", systemImage: "curlybraces.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                selectedTab = .diagnostics
                runDiagnostics()
            } label: {
                Label("运行连接诊断", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(isRunningDiagnostics)
        }
        .buttonStyle(.bordered)
        .sshocksPanelCard()
        .frame(minWidth: SSHocksVisual.compactColumnWidth, maxWidth: SSHocksVisual.primaryColumnWidth, alignment: .topLeading)
    }

    private var recentServersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                panelHeader("最近服务器", systemImage: "clock.arrow.circlepath")

                Spacer()

                Button {
                    selectedTab = .profiles
                } label: {
                    Label("全部", systemImage: "list.bullet")
                }
            }

            if recentProfiles.isEmpty {
                ContentUnavailableView(
                    "还没有已鉴权服务器",
                    systemImage: "server.rack",
                    description: Text("成功连接一次后，服务器会出现在这里。")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentProfiles) { profile in
                        profileRow(profile)
                        if profile.id != recentProfiles.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .sshocksPanelCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var clashForm: some View {
        VStack(alignment: .leading, spacing: SSHocksVisual.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                panelHeader("节点", systemImage: "network")

                VStack(spacing: 0) {
                    formRow("节点名称") {
                        TextField("Termius SSH SOCKS", text: $proxyName)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }

                    Divider()

                    formRow("server") {
                        Text("127.0.0.1")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Divider()

                    formRow("port") {
                        TextField("1080", value: $localPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .frame(width: 96)
                    }
                }
            }
            .sshocksPanelCard()

            VStack(alignment: .leading, spacing: 12) {
                panelHeader("规则", systemImage: "list.bullet.rectangle")

                VStack(alignment: .leading, spacing: 0) {
                    toggleRow("国内流量直连", isOn: $directChinaTraffic)

                    Divider()

                    toggleRow("未命中规则默认走代理", isOn: $matchProxy)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("需要走代理的域名后缀")
                        .font(.callout.weight(.semibold))

                    TextEditor(text: $proxiedDomains)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 170)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.7)
                        }
                }
                .padding(.top, 2)
            }
            .sshocksPanelCard()
        }
        .sshocksPrimaryColumn()
    }

    @ViewBuilder
    private var diagnosticHints: some View {
        diagnosticHint(
            title: "端口被占用",
            value: "把本地端口改成 1081、2080 或其他空闲端口。"
        )
        diagnosticHint(
            title: "认证失败",
            value: "确认密码、私钥权限、用户名和服务器 SSH 端口。"
        )
        diagnosticHint(
            title: "浏览器无法访问",
            value: "浏览器或 Clash 应使用 SOCKS5 127.0.0.1:\(localPort)。"
        )
    }

    private var profileListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                panelHeader("已鉴权服务器", systemImage: "checkmark.seal")
                Spacer()
                Button {
                    profileEditorDraft = SSHProfileDraft()
                } label: {
                    Label("新增", systemImage: "plus")
                }

                Button {
                    selectedTab = .connect
                } label: {
                    Label("连接页", systemImage: "plus.circle")
                }
            }

            Text(serverPoolMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("搜索名称、主机、用户名、分组或标签", text: $profileSearchInput)
                    .textFieldStyle(.roundedBorder)

                Picker("排序", selection: $profileSortOption) {
                    ForEach(ProfileSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            List {
                if profiles.isEmpty {
                    ContentUnavailableView(
                        "服务器池为空",
                        systemImage: "server.rack",
                        description: Text("先在“连接”页成功启动一次 SSH 代理，服务器会自动加入池子。")
                    )
                } else if filteredProfiles.isEmpty {
                    ContentUnavailableView(
                        "没有匹配服务器",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词，或清空搜索条件。")
                    )
                } else {
                    ForEach(groupedFilteredProfiles, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.profiles) { profile in
                                profileRow(profile)
                            }
                            .onDelete { offsets in
                                deleteProfiles(offsets, in: group.profiles)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .sshocksPanelCard()
        .sshocksSideColumn()
    }

    private var profileInfoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("保存内容", systemImage: "lock.doc")

            Text("服务器池支持新增、查看、编辑和删除。密码登录的密码会写入 macOS Keychain；服务器池本身只保存连接元数据。")
                .foregroundStyle(.secondary)

            Divider()

            panelHeader("建议", systemImage: "key")

            Text("从服务器池点击“连接”会自动载入本地 SOCKS5 端口、节点名和鉴权方式，然后立即启动。")
                .foregroundStyle(.secondary)
        }
        .sshocksPanelCard()
        .frame(minWidth: SSHocksVisual.compactColumnWidth, maxWidth: SSHocksVisual.primaryColumnWidth, alignment: .topLeading)
    }

    private func detailContainer<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                statusBadge
            }
            .frame(maxWidth: SSHocksVisual.pageMaxWidth, alignment: .leading)

            ScrollView {
                content()
                    .frame(maxWidth: SSHocksVisual.pageMaxWidth, alignment: .topLeading)
                    .padding(.bottom, 28)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SSHocksVisual.pagePadding)
        .padding(.vertical, 26)
    }

    private var statusBadge: some View {
        let (title, color): (String, Color) = {
            switch tunnelManager.state {
            case .idle:
                return ("未连接", .secondary)
            case .connecting:
                return ("连接中", .orange)
            case .connected:
                return ("已连接", .green)
            case .failed:
                return ("连接失败", .red)
            }
        }()

        return Label(title, systemImage: "circle.fill")
            .foregroundStyle(color)
            .font(.headline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary, in: Capsule())
    }

    private func panelHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .labelStyle(.titleAndIcon)
    }

    private func formRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 116, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 34)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: isOn)
                .labelsHidden()

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private func statusControlRow<Actions: View>(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Spacer(minLength: 12)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        actions()
                    }

                    Menu {
                        actions()
                    } label: {
                        Label("操作", systemImage: "ellipsis.circle")
                    }
                }
                .buttonStyle(.bordered)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader("SSH 服务器", systemImage: "server.rack")

            VStack(spacing: 0) {
                formRow("服务器地址") {
                    TextField("example.com", text: $draftSSHHost)
                        .textContentType(.URL)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }

                Divider()

                formRow("端口") {
                    HStack(spacing: 8) {
                        Text("默认 22")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("22", value: $draftSSHPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .frame(width: 72)
                    }
                }

                Divider()

                formRow("用户名") {
                    TextField("root", text: $draftSSHUsername)
                        .textContentType(.username)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }
        }
        .sshocksPanelCard()
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader("访问鉴权", systemImage: "key")

            VStack(spacing: 0) {
                formRow("方式") {
                    Picker("方式", selection: draftAuthMethodBinding) {
                        ForEach(AuthMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                Divider()

                if draftAuthMethod == .password {
                    formRow("SSH 密码") {
                        SecureField("可留空后手动输入", text: $sshPassword)
                            .textContentType(.password)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }
                } else {
                    formRow("私钥路径") {
                        HStack(spacing: 10) {
                            TextField("~/.ssh/id_ed25519", text: $draftPrivateKeyPath)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Button {
                                choosePrivateKey()
                            } label: {
                                Label("选择", systemImage: "folder")
                            }
                        }
                    }

                    Divider()

                    Text("支持无密码私钥，或已加载到 SSH Agent 的私钥。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .sshocksPanelCard()
    }

    private var localProxySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader("本地代理", systemImage: "network")

            VStack(spacing: 0) {
                formRow("监听地址") {
                    Text("127.0.0.1")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()

                formRow("本地端口") {
                    TextField("1080", value: $draftLocalPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .frame(width: 96)
                }

                Divider()

                formRow("节点名称") {
                    TextField("Termius SSH SOCKS", text: $draftProxyName)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    startTunnel()
                } label: {
                    Label("连接并启动代理", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(tunnelManager.isRunning)

                Button {
                    tunnelManager.stop()
                } label: {
                    Label("断开", systemImage: "stop.fill")
                }
                .disabled(!tunnelManager.isRunning)

                Spacer()
            }
            .padding(.top, 6)
        }
        .sshocksPanelCard()
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader("当前状态", systemImage: "network")

            Text(tunnelManager.detail)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Text(proxyAddress)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    copy(connectionProxyAddress)
                    copiedProxyAddress = true
                } label: {
                    Label(copiedProxyAddress ? "已复制" : "复制", systemImage: "doc.on.doc")
                }
            }

            Divider()

            statusControlRow(
                title: healthMonitor.state.title,
                detail: healthMonitor.detail,
                symbol: healthMonitor.state.symbol,
                tint: healthMonitor.state.color
            ) {
                Button {
                    Task {
                        await healthMonitor.checkNow(port: localPort)
                    }
                } label: {
                    Label("立即检测", systemImage: "waveform.path.ecg")
                }
                .disabled(!tunnelManager.isRunning)
            }

            Divider()

            statusControlRow(
                title: systemProxyManager.isEnabled ? "系统代理已开启" : "系统代理未开启",
                detail: systemProxyManager.detail,
                symbol: systemProxyManager.isEnabled ? "network" : "circle",
                tint: systemProxyManager.isEnabled ? .green : .secondary
            ) {
                Button {
                    enableSystemProxy()
                } label: {
                    Label("开启", systemImage: "power")
                }
                .disabled(systemProxyManager.isWorking)

                Button {
                    disableSystemProxy()
                } label: {
                    Label("关闭", systemImage: "xmark.circle")
                }
                .disabled(systemProxyManager.isWorking)
            }

            Divider()

            statusControlRow(
                title: tunModeManager.isEnabled ? "TUN 模式已开启" : "TUN 模式未开启",
                detail: tunModeManager.detail,
                symbol: tunModeManager.state.symbol,
                tint: tunModeManager.isEnabled ? .green : .secondary
            ) {
                Button {
                    tunModeEnabled = true
                    enableTUNMode()
                } label: {
                    Label("开启", systemImage: "power")
                }
                .disabled(tunModeManager.isEnabled || tunModeManager.isInstallingPackage)

                Button {
                    installTUNPackage()
                } label: {
                    Label(
                        tunModeManager.isInstallingPackage ? "安装中" : "安装套件",
                        systemImage: "shippingbox"
                    )
                }
                .disabled(tunModeManager.isInstallingPackage)

                Button {
                    tunModeEnabled = false
                    disableTUNMode()
                } label: {
                    Label("关闭", systemImage: "xmark.circle")
                }
            }
        }
        .sshocksPanelCard()
    }

    private var quickActionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("快捷操作", systemImage: "sparkles")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    quickActionButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    quickActionButtons
                }
            }
        }
        .buttonStyle(.bordered)
        .sshocksPanelCard()
    }

    @ViewBuilder
    private var quickActionButtons: some View {
        Button {
            selectedTab = .clash
        } label: {
            Label("编辑 Clash 片段", systemImage: "curlybraces")
        }

        Button {
            selectedTab = .diagnostics
            runDiagnostics()
        } label: {
            Label("诊断连接", systemImage: "stethoscope")
        }

        Button {
            selectedTab = .profiles
        } label: {
            Label("服务器池", systemImage: "server.rack")
        }
    }

    private var clashPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                panelHeader("生成结果", systemImage: "doc.plaintext")

                Spacer()

                Button {
                    copy(clashYAML)
                    copiedClashYAML = true
                } label: {
                    Label(copiedClashYAML ? "已复制" : "复制 YAML", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                Text(clashYAML)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(minHeight: 420, maxHeight: 520)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.7)
            }
        }
        .sshocksPanelCard()
        .sshocksSideColumn()
    }

    @ViewBuilder
    private var logPanel: some View {
        if tunnelManager.hasLog {
            VStack(alignment: .leading, spacing: 10) {
                panelHeader("SSH 输出", systemImage: "terminal")

                ScrollView {
                    Text(tunnelManager.log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 120, maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .sshocksPanelCard()
            .onAppear {
                tunnelManager.setLogPublishingEnabled(true)
            }
            .onDisappear {
                tunnelManager.setLogPublishingEnabled(false)
            }
        }
    }

    private func diagnosticHint(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sshocksPanelCard()
    }

    private func profileRow(_ profile: SSHProfile) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleFavorite(profile)
            } label: {
                Image(systemName: profile.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(profile.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                Text("\(profile.username)@\(profile.host):\(profile.sshPort)  ->  127.0.0.1:\(profile.localPort)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(profile.authMethod.title, systemImage: profile.authMethod == .password ? "key" : "doc.badge.gearshape")
                    Label(profile.groupName, systemImage: "folder")
                    Text("已连接 \(profile.connectionCount) 次")
                    Text("最近 \(profile.lastConnectedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !profile.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(profile.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }

            Spacer()

            Button {
                applyProfile(profile)
            } label: {
                Label("载入", systemImage: "arrow.down.circle")
            }

            Button {
                profileEditorDraft = SSHProfileDraft(profile: profile)
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button {
                connectProfile(profile)
            } label: {
                Label("连接", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                deleteProfile(profile)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .padding(.vertical, 6)
    }

    private var clashYAML: String {
        let domainLines = proxiedDomains
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "  - DOMAIN-SUFFIX,\($0),PROXY" }
            .joined(separator: "\n")

        var rules = [String]()
        if !domainLines.isEmpty {
            rules.append(domainLines)
        }
        if directChinaTraffic {
            rules.append("  - GEOIP,CN,DIRECT")
        }
        rules.append(matchProxy ? "  - MATCH,PROXY" : "  - MATCH,DIRECT")

        return """
        proxies:
          - name: \(yamlQuote(proxyName))
            type: socks5
            server: 127.0.0.1
            port: \(localPort)

        proxy-groups:
          - name: "PROXY"
            type: select
            proxies:
              - \(yamlQuote(proxyName))
              - DIRECT

        rules:
        \(rules.joined(separator: "\n"))
        """
    }

    private func hydrateConnectionDraftIfNeeded() {
        guard !connectionDraftHydrated else { return }
        draftSSHHost = sshHost
        draftSSHPort = sshPort
        draftSSHUsername = sshUsername
        draftPrivateKeyPath = privateKeyPath
        draftLocalPort = localPort
        draftProxyName = proxyName
        draftAuthMethod = AuthMethod(rawValue: authMethodRawValue) ?? .password
        profileSearchInput = profileSearchText
        connectionDraftHydrated = true
    }

    private func persistConnectionDraft() {
        sshHost = draftSSHHost
        sshPort = draftSSHPort
        sshUsername = draftSSHUsername
        privateKeyPath = draftPrivateKeyPath
        localPort = draftLocalPort
        proxyName = draftProxyName
        authMethodRawValue = draftAuthMethod.rawValue
    }

    private func startTunnel() {
        copiedClashYAML = false
        copiedProxyAddress = false
        persistConnectionDraft()

        tunnelManager.start(
            host: draftSSHHost,
            sshPort: draftSSHPort,
            username: draftSSHUsername,
            password: sshPassword,
            privateKeyPath: draftPrivateKeyPath,
            localPort: draftLocalPort,
            authMethod: draftAuthMethod,
            autoReconnect: autoReconnectEnabled
        )

        if autoCopyProxyAddress {
            copy(connectionProxyAddress)
            copiedProxyAddress = true
        }
    }

    private func rememberAuthenticatedServer() {
        let trimmedHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = sshUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeyPath = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty, !trimmedUsername.isEmpty else {
            return
        }

        let now = Date()
        let displayName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (proxyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trimmedHost : proxyName)
            : profileName.trimmingCharacters(in: .whitespacesAndNewlines)

        let candidate = SSHProfile(
            name: displayName,
            host: trimmedHost,
            sshPort: sshPort,
            username: trimmedUsername,
            localPort: localPort,
            proxyName: proxyName,
            authMethod: authMethod.wrappedValue,
            privateKeyPath: trimmedKeyPath,
            verifiedAt: now,
            lastConnectedAt: now,
            connectionCount: 1
        )

        let profileIndex = profiles.firstIndex { $0.endpointKey == candidate.endpointKey }
        let profileID = profileIndex.map { profiles[$0].id } ?? candidate.id
        var keychainErrorMessage: String?

        if authMethod.wrappedValue == .password, !sshPassword.isEmpty {
            do {
                try KeychainStore.savePassword(sshPassword, account: profileID.uuidString)
            } catch {
                keychainErrorMessage = "服务器已鉴权，但密码保存到 Keychain 失败：\(error.localizedDescription)"
            }
        }

        if let profileIndex {
            let existing = profiles[profileIndex]
            profiles[profileIndex] = SSHProfile(
                id: existing.id,
                name: displayName,
                host: trimmedHost,
                sshPort: sshPort,
                username: trimmedUsername,
                localPort: localPort,
                proxyName: proxyName,
                authMethod: authMethod.wrappedValue,
                privateKeyPath: trimmedKeyPath,
                verifiedAt: existing.verifiedAt,
                lastConnectedAt: now,
                connectionCount: existing.connectionCount + 1,
                groupName: existing.groupName,
                tags: existing.tags,
                isFavorite: existing.isFavorite
            )
        } else {
            profiles.append(candidate)
        }

        profiles.sort { $0.lastConnectedAt > $1.lastConnectedAt }
        SSHProfileStore.save(profiles)
        serverPoolMessage = keychainErrorMessage ?? "已更新服务器池：\(trimmedUsername)@\(trimmedHost):\(sshPort)"
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.title = "选择 SSH 私钥"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            draftPrivateKeyPath = url.path
        }
    }

    private func upsertProfile(_ draft: SSHProfileDraft) {
        let profile = draft.profile
        var keychainMessage: String?

        if profile.authMethod == .password {
            do {
                try KeychainStore.savePassword(draft.password, account: profile.keychainAccount)
            } catch {
                keychainMessage = "，但密码保存到 Keychain 失败：\(error.localizedDescription)"
            }
        } else {
            KeychainStore.deletePassword(account: profile.keychainAccount)
        }

        if let existingIndex = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[existingIndex] = profile
        } else if let duplicateIndex = profiles.firstIndex(where: { $0.endpointKey == profile.endpointKey }) {
            let duplicate = profiles[duplicateIndex]
            KeychainStore.deletePassword(account: duplicate.keychainAccount)
            profiles[duplicateIndex] = profile
        } else {
            profiles.append(profile)
        }

        profiles.sort { $0.lastConnectedAt > $1.lastConnectedAt }
        SSHProfileStore.save(profiles)
        serverPoolMessage = "\(draft.isNew ? "已新增" : "已更新")服务器：\(profile.name)\(keychainMessage ?? "")"
    }

    private func applyProfile(_ profile: SSHProfile) {
        draftSSHHost = profile.host
        draftSSHPort = profile.sshPort
        draftSSHUsername = profile.username
        draftLocalPort = profile.localPort
        draftProxyName = profile.proxyName
        draftAuthMethod = profile.authMethod
        draftPrivateKeyPath = profile.privateKeyPath
        profileName = profile.name
        if profile.authMethod == .password {
            sshPassword = KeychainStore.password(account: profile.keychainAccount) ?? ""
        }
        serverPoolMessage = "已载入 \(profile.name)。"
    }

    private func connectProfile(_ profile: SSHProfile) {
        applyProfile(profile)

        if profile.authMethod == .password {
            guard let password = KeychainStore.password(account: profile.keychainAccount), !password.isEmpty else {
                selectedTab = .connect
                serverPoolMessage = "未在 Keychain 找到 \(profile.name) 的密码，请在连接页重新输入密码并连接一次。"
                return
            }
            sshPassword = password
        }

        persistConnectionDraft()
        selectedTab = .connect
        tunnelManager.start(
            host: profile.host,
            sshPort: profile.sshPort,
            username: profile.username,
            password: sshPassword,
            privateKeyPath: profile.privateKeyPath,
            localPort: profile.localPort,
            authMethod: profile.authMethod,
            autoReconnect: autoReconnectEnabled
        )
    }

    private func deleteProfiles(at offsets: IndexSet) {
        for offset in offsets {
            guard profiles.indices.contains(offset) else { continue }
            KeychainStore.deletePassword(account: profiles[offset].keychainAccount)
        }
        profiles.remove(atOffsets: offsets)
        SSHProfileStore.save(profiles)
        serverPoolMessage = profiles.isEmpty ? "服务器池已清空。" : "已删除服务器。"
    }

    private func deleteProfiles(_ offsets: IndexSet, in visibleProfiles: [SSHProfile]) {
        for offset in offsets {
            guard visibleProfiles.indices.contains(offset) else { continue }
            deleteProfile(visibleProfiles[offset])
        }
    }

    private func deleteProfile(_ profile: SSHProfile) {
        KeychainStore.deletePassword(account: profile.keychainAccount)
        profiles.removeAll { $0.id == profile.id }
        SSHProfileStore.save(profiles)
        serverPoolMessage = profiles.isEmpty ? "服务器池已清空。" : "已删除 \(profile.name)。"
    }

    private func toggleFavorite(_ profile: SSHProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].isFavorite.toggle()
        SSHProfileStore.save(profiles)
        serverPoolMessage = profiles[index].isFavorite ? "已收藏 \(profile.name)。" : "已取消收藏 \(profile.name)。"
    }

    private func loadNetworkServicesIfNeeded() async {
        await systemProxyManager.loadServices()
        if selectedNetworkService.isEmpty {
            selectedNetworkService = systemProxyManager.services.first(where: { $0 == "Wi-Fi" })
                ?? systemProxyManager.services.first
                ?? ""
        }
        await systemProxyManager.refresh(service: activeNetworkService)
    }

    private func refreshSystemProxy() {
        Task {
            await systemProxyManager.loadServices()
            if selectedNetworkService.isEmpty {
                selectedNetworkService = systemProxyManager.services.first(where: { $0 == "Wi-Fi" })
                    ?? systemProxyManager.services.first
                    ?? ""
            }
            await systemProxyManager.refresh(service: activeNetworkService)
        }
    }

    private func enableSystemProxy() {
        Task {
            await systemProxyManager.enable(service: activeNetworkService, port: localPort)
        }
    }

    private func disableSystemProxy() {
        Task {
            await systemProxyManager.disable(service: activeNetworkService)
        }
    }

    private func enableTUNMode() {
        Task {
            let didEnable = await tunModeManager.enable(localPort: localPort, tunnelRunning: tunnelManager.isRunning)
            if !didEnable {
                tunModeEnabled = false
            }
        }
    }

    private func installTUNPackage() {
        Task {
            let didInstall = await tunModeManager.installEnginePackage()
            if didInstall, tunModeEnabled, tunnelManager.isRunning {
                enableTUNMode()
            }
        }
    }

    private func disableTUNMode() {
        tunModeManager.disable()
    }

    private func runDiagnostics() {
        let host = sshHost
        let port = sshPort
        let local = localPort
        let running = tunnelManager.isRunning

        isRunningDiagnostics = true
        diagnosticsLog = "正在诊断..."

        Task {
            let report = await DiagnosticRunner.run(
                host: host,
                sshPort: port,
                localPort: local,
                tunnelRunning: running
            )
            diagnosticsLog = report
            isRunningDiagnostics = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func yamlQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

#Preview {
    ContentView(
        tunnelManager: SSHTunnelManager(),
        systemProxyManager: SystemProxyManager(),
        healthMonitor: ProxyHealthMonitor(),
        tunModeManager: TUNModeManager()
    )
}
