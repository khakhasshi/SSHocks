//
//  SSHocksMenuBarView.swift
//  SSHocks
//
//  Created by Codex on 17/6/2026.
//

import AppKit
import SwiftUI

struct SSHocksMenuBarLabel: View {
    @ObservedObject var statusSummary: TunnelStatusSummary

    private var state: TunnelState {
        statusSummary.state
    }

    var body: some View {
        ZStack(alignment: .center) {
            Image(systemName: "server.rack")
                .font(.system(size: 14, weight: .semibold))
                .offset(x: -3, y: 0)

            Image(systemName: "network")
                .font(.system(size: 10, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .background(.bar, in: Circle())
                .offset(x: 6, y: -1)

            Image(systemName: badgeSymbolName)
                .font(.system(size: 7, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(badgeColor, Color(nsColor: .controlBackgroundColor))
                .background(.bar, in: Circle())
                .offset(x: 8, y: 6)
        }
        .frame(width: 26, height: 18)
        .help(helpText)
    }

    private var badgeSymbolName: String {
        switch state {
        case .idle:
            return "circle"
        case .connecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var badgeColor: Color {
        switch state {
        case .idle:
            return .secondary
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    private var helpText: String {
        switch state {
        case .idle:
            return "SSHocks 未连接"
        case .connecting:
            return "SSHocks 正在连接"
        case .connected:
            return "SSHocks SOCKS5 代理已连接"
        case .failed:
            return "SSHocks 连接失败"
        }
    }
}

struct SSHocksMenuBarView: View {
    let tunnelManager: SSHTunnelManager
    @ObservedObject var statusSummary: TunnelStatusSummary
    @ObservedObject var systemProxyManager: SystemProxyManager
    @ObservedObject var tunModeManager: TUNModeManager

    @Environment(\.openWindow) private var openWindow

    @AppStorage("sshHost") private var sshHost = ""
    @AppStorage("sshPort") private var sshPort = 22
    @AppStorage("sshUsername") private var sshUsername = ""
    @AppStorage("privateKeyPath") private var privateKeyPath = ""
    @AppStorage("localPort") private var localPort = 1080
    @AppStorage("proxyName") private var proxyName = "Termius SSH SOCKS"
    @AppStorage("authMethod") private var authMethodRawValue = AuthMethod.password.rawValue
    @AppStorage("selectedNetworkService") private var selectedNetworkService = ""
    @AppStorage("autoReconnectEnabled") private var autoReconnectEnabled = true
    @AppStorage("tunModeEnabled") private var tunModeEnabled = false

    @State private var profiles = SSHProfileStore.load()
    @State private var activeMenuProfile: SSHProfile?
    @State private var menuMessage = ""

    private var proxyAddress: String {
        "socks5://127.0.0.1:\(localPort)"
    }

    private var activeNetworkService: String {
        if !selectedNetworkService.isEmpty {
            return selectedNetworkService
        }
        return systemProxyManager.services.first ?? "Wi-Fi"
    }

    private var statusTitle: String {
        switch statusSummary.state {
        case .idle:
            return "未连接"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        case .failed:
            return "连接失败"
        }
    }

    private var statusSymbol: String {
        switch statusSummary.state {
        case .idle:
            return "circle"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var body: some View {
        Group {
            Section {
                Label(statusTitle, systemImage: statusSymbol)
                Text(statusSummary.detail)
                Text(proxyAddress)
            }

            Section {
                Button {
                    copy(proxyAddress)
                    menuMessage = "已复制 SOCKS5 地址"
                } label: {
                    Label("复制 SOCKS5 地址", systemImage: "doc.on.doc")
                }

                if statusSummary.isRunning {
                    Button {
                        tunnelManager.stop()
                        menuMessage = "已断开连接"
                    } label: {
                        Label("断开连接", systemImage: "stop.fill")
                    }
                }
            }

            Section("系统代理") {
                Label(
                    systemProxyManager.isEnabled ? "已开启：\(activeNetworkService)" : "未开启：\(activeNetworkService)",
                    systemImage: systemProxyManager.isEnabled ? "network" : "circle"
                )

                Button {
                    enableSystemProxy()
                } label: {
                    Label("开启系统代理", systemImage: "power")
                }
                .disabled(systemProxyManager.isWorking)

                Button {
                    disableSystemProxy()
                } label: {
                    Label("关闭系统代理", systemImage: "xmark.circle")
                }
                .disabled(systemProxyManager.isWorking)
            }

            Section("TUN 模式") {
                Label(tunModeManager.state.title, systemImage: tunModeManager.state.symbol)
                Text(tunModeManager.detail)

                Button {
                    tunModeEnabled = true
                    enableTUNMode()
                } label: {
                    Label("开启 TUN 模式", systemImage: "power")
                }
                .disabled(tunModeManager.isEnabled || tunModeManager.isInstallingPackage)

                Button {
                    tunModeEnabled = false
                    disableTUNMode()
                } label: {
                    Label("关闭 TUN 模式", systemImage: "xmark.circle")
                }

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
                    tunModeManager.refreshAvailability()
                    menuMessage = "已检测 TUN 引擎"
                } label: {
                    Label("检测 TUN 引擎", systemImage: "magnifyingglass")
                }
                .disabled(tunModeManager.isInstallingPackage)
            }

            Section("服务器池") {
                if profiles.isEmpty {
                    Text("暂无已鉴权服务器")
                } else {
                    ForEach(profiles.prefix(5)) { profile in
                        Button {
                            start(profile)
                        } label: {
                            Label("\(profile.name) · \(profile.groupName)", systemImage: profile.isFavorite ? "star.fill" : "play.fill")
                        }
                        .disabled(statusSummary.state == .connecting)
                    }
                }

                Button {
                    refreshProfiles()
                    menuMessage = "已刷新服务器池"
                } label: {
                    Label("刷新服务器池", systemImage: "arrow.clockwise")
                }
            }

            if !menuMessage.isEmpty {
                Section {
                    Text(menuMessage)
                }
            }

            Section {
                Button {
                    openMainWindow()
                } label: {
                    Label("打开 SSHocks", systemImage: "macwindow")
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 SSHocks", systemImage: "power")
                }
            }
        }
        .onAppear {
            refreshProfiles()
            tunModeManager.refreshAvailability()
            Task {
                await loadNetworkServicesIfNeeded()
            }
        }
        .onChange(of: statusSummary.state) { _, newState in
            if newState == .connected {
                if tunModeEnabled {
                    enableTUNMode()
                }
                guard let activeMenuProfile else { return }
                markProfileConnected(activeMenuProfile)
                self.activeMenuProfile = nil
            }

            if case .failed = newState {
                disableTUNMode()
            }
        }
    }

    private func start(_ profile: SSHProfile) {
        sshHost = profile.host
        sshPort = profile.sshPort
        sshUsername = profile.username
        privateKeyPath = profile.privateKeyPath
        localPort = profile.localPort
        proxyName = profile.proxyName
        authMethodRawValue = profile.authMethod.rawValue

        let password: String
        if profile.authMethod == .password {
            guard let storedPassword = KeychainStore.password(account: profile.keychainAccount), !storedPassword.isEmpty else {
                menuMessage = "未找到 \(profile.name) 的 Keychain 密码，请在主窗口重新连接一次。"
                openMainWindow()
                return
            }
            password = storedPassword
        } else {
            password = ""
        }

        activeMenuProfile = profile
        menuMessage = "正在连接 \(profile.name)..."
        tunnelManager.start(
            host: profile.host,
            sshPort: profile.sshPort,
            username: profile.username,
            password: password,
            privateKeyPath: profile.privateKeyPath,
            localPort: profile.localPort,
            authMethod: profile.authMethod,
            autoReconnect: autoReconnectEnabled
        )
    }

    private func markProfileConnected(_ profile: SSHProfile) {
        refreshProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }

        let existing = profiles[index]
        profiles[index] = SSHProfile(
            id: existing.id,
            name: existing.name,
            host: existing.host,
            sshPort: existing.sshPort,
            username: existing.username,
            localPort: existing.localPort,
            proxyName: existing.proxyName,
            authMethod: existing.authMethod,
            privateKeyPath: existing.privateKeyPath,
            verifiedAt: existing.verifiedAt,
            lastConnectedAt: Date(),
            connectionCount: existing.connectionCount + 1,
            groupName: existing.groupName,
            tags: existing.tags,
            isFavorite: existing.isFavorite
        )
        profiles.sort { $0.lastConnectedAt > $1.lastConnectedAt }
        SSHProfileStore.save(profiles)
        menuMessage = "已连接 \(existing.name)"
    }

    private func refreshProfiles() {
        profiles = SSHProfileStore.load().sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            return lhs.lastConnectedAt > rhs.lastConnectedAt
        }
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
            let didEnable = await tunModeManager.enable(localPort: localPort, tunnelRunning: statusSummary.isRunning)
            menuMessage = didEnable ? "TUN 模式已开启" : "TUN 模式未能开启"
            if !didEnable {
                tunModeEnabled = false
            }
        }
    }

    private func installTUNPackage() {
        Task {
            let didInstall = await tunModeManager.installEnginePackage()
            menuMessage = didInstall ? "TUN 套件已安装" : "TUN 套件未能安装"
            if didInstall, tunModeEnabled, statusSummary.isRunning {
                enableTUNMode()
            }
        }
    }

    private func disableTUNMode() {
        tunModeManager.disable()
        menuMessage = "TUN 模式已关闭"
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
