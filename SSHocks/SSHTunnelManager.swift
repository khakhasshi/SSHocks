//
//  SSHTunnelManager.swift
//  SSHocks
//
//  Created by Codex on 17/6/2026.
//

import Combine
import Darwin
import Foundation
import Network

enum TunnelState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

@MainActor
final class TunnelStatusSummary: ObservableObject {
    @Published private(set) var state: TunnelState = .idle
    @Published private(set) var detail = "尚未连接"
    @Published private(set) var isRunning = false

    func update(state: TunnelState, detail: String, isRunning: Bool) {
        guard self.state != state || self.detail != detail || self.isRunning != isRunning else {
            return
        }

        self.state = state
        self.detail = detail
        self.isRunning = isRunning
    }
}

private struct SSHConnectionRequest {
    var host: String
    var sshPort: Int
    var username: String
    var password: String
    var privateKeyPath: String
    var localPort: Int
    var authMethod: AuthMethod
}

@MainActor
final class SSHTunnelManager: ObservableObject {
    let statusSummary = TunnelStatusSummary()

    @Published private(set) var state: TunnelState = .idle {
        didSet { updateStatusSummary() }
    }
    @Published private(set) var detail = "尚未连接" {
        didSet { updateStatusSummary() }
    }
    @Published private(set) var log = ""
    @Published private(set) var hasLog = false
    @Published private(set) var reconnectAttempt = 0

    private var process: Process? {
        didSet { updateStatusSummary() }
    }
    private var askPassScriptURL: URL?
    private var stderrPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var lastRequest: SSHConnectionRequest?
    private var reconnectTask: Task<Void, Never>?
    private var autoReconnectEnabled = false
    private var manualStopRequested = false
    private var logBuffer = ""
    private var logPublishTask: Task<Void, Never>?
    private var logPublishingEnabled = false
    private var networkAvailable = true
    private var networkWaiters: [NetworkWaiter] = []
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "SSHocks.NetworkPathMonitor", qos: .utility)

    private let maxReconnectAttempts = 3

    private struct NetworkWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.updateNetworkAvailability(isAvailable)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        updateStatusSummary()
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    private func updateStatusSummary() {
        statusSummary.update(state: state, detail: detail, isRunning: isRunning)
    }

    func start(
        host: String,
        sshPort: Int,
        username: String,
        password: String,
        privateKeyPath: String,
        localPort: Int,
        authMethod: AuthMethod,
        autoReconnect: Bool = false
    ) {
        let request = SSHConnectionRequest(
            host: host,
            sshPort: sshPort,
            username: username,
            password: password,
            privateKeyPath: privateKeyPath,
            localPort: localPort,
            authMethod: authMethod
        )
        start(request, autoReconnect: autoReconnect, resetReconnectAttempts: true)
    }

    private func start(
        _ request: SSHConnectionRequest,
        autoReconnect: Bool,
        resetReconnectAttempts: Bool
    ) {
        stopRunningProcess(resetState: false)
        reconnectTask?.cancel()
        manualStopRequested = false
        autoReconnectEnabled = autoReconnect
        lastRequest = request

        if resetReconnectAttempts {
            reconnectAttempt = 0
        }
        clearLog()

        let trimmedHost = request.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = request.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKeyPath = request.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            fail("请填写服务器地址。")
            return
        }

        guard !trimmedUser.isEmpty else {
            fail("请填写 SSH 用户名。")
            return
        }

        guard (1...65535).contains(request.sshPort), (1...65535).contains(request.localPort) else {
            fail("端口必须在 1 到 65535 之间。")
            return
        }

        if request.authMethod == .password, request.password.isEmpty {
            fail("请选择密码登录时，需要填写 SSH 密码。")
            return
        }

        if request.authMethod == .privateKey, trimmedKeyPath.isEmpty {
            fail("请选择密钥登录时，需要选择私钥文件。")
            return
        }

        var arguments = [
            "-N",
            "-D", "127.0.0.1:\(request.localPort)",
            "-p", "\(request.sshPort)",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=12",
            "-o", "StrictHostKeyChecking=accept-new"
        ]

        var environment = ProcessInfo.processInfo.environment

        switch request.authMethod {
        case .password:
            do {
                let scriptURL = try makeAskPassScript()
                askPassScriptURL = scriptURL
                environment["SSH_ASKPASS"] = scriptURL.path
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["DISPLAY"] = "SSHocks"
                environment["SSHOCKS_ASKPASS_SECRET"] = request.password
                arguments += [
                    "-o", "PreferredAuthentications=password,keyboard-interactive",
                    "-o", "PubkeyAuthentication=no"
                ]
            } catch {
                fail("无法准备密码鉴权脚本：\(error.localizedDescription)")
                return
            }

        case .privateKey:
            arguments += [
                "-i", trimmedKeyPath,
                "-o", "IdentitiesOnly=yes",
                "-o", "PreferredAuthentications=publickey"
            ]
        }

        arguments.append("\(trimmedUser)@\(trimmedHost)")

        let sshProcess = Process()
        sshProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        sshProcess.arguments = arguments
        sshProcess.environment = environment

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        self.stderrPipe = stderrPipe
        self.stdoutPipe = stdoutPipe
        sshProcess.standardError = stderrPipe
        sshProcess.standardOutput = stdoutPipe

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendLog(text)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendLog(text)
            }
        }

        sshProcess.terminationHandler = { [weak self] finishedProcess in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let exitMessage = self.messageForTerminatedProcess(finishedProcess)
                self.process = nil
                self.cleanupAfterProcess()

                if self.shouldReconnect {
                    self.scheduleReconnect(reason: exitMessage)
                } else if case .connecting = self.state {
                    self.fail(exitMessage)
                } else if case .connected = self.state {
                    self.state = .failed(exitMessage)
                    self.detail = exitMessage
                }
            }
        }

        do {
            state = .connecting
            detail = reconnectAttempt > 0
                ? "正在自动重连 \(trimmedUser)@\(trimmedHost):\(request.sshPort)（\(reconnectAttempt)/\(maxReconnectAttempts)）..."
                : "正在连接 \(trimmedUser)@\(trimmedHost):\(request.sshPort)..."
            process = sshProcess
            try sshProcess.run()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.8))
                guard let self, self.process === sshProcess, sshProcess.isRunning else { return }
                self.state = .connected
                self.detail = "SOCKS5 代理已启动：127.0.0.1:\(request.localPort)"
            }
        } catch {
            cleanupAfterProcess()
            fail("无法启动 /usr/bin/ssh：\(error.localizedDescription)")
        }
    }

    func stop() {
        manualStopRequested = true
        autoReconnectEnabled = false
        reconnectTask?.cancel()
        reconnectTask = nil
        logPublishTask?.cancel()
        logPublishTask = nil
        reconnectAttempt = 0
        stopRunningProcess(resetState: true)
    }

    func shutdownForTermination() {
        manualStopRequested = true
        autoReconnectEnabled = false
        reconnectTask?.cancel()
        reconnectTask = nil
        logPublishTask?.cancel()
        logPublishTask = nil
        networkWaiters.forEach { $0.continuation.resume() }
        networkWaiters.removeAll()

        if let process {
            let pid = process.processIdentifier
            if process.isRunning {
                kill(pid, SIGTERM)
                usleep(250_000)
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
                process.waitUntilExit()
            }
            self.process = nil
        }

        cleanupAfterProcess()
        state = .idle
        detail = "已断开连接"
    }

    func setLogPublishingEnabled(_ enabled: Bool) {
        logPublishingEnabled = enabled
        if enabled {
            flushLog()
        } else {
            logPublishTask?.cancel()
            logPublishTask = nil
            log = ""
        }
    }

    private func stopRunningProcess(resetState: Bool) {
        guard let process else {
            cleanupAfterProcess()
            if resetState {
                state = .idle
                detail = "尚未连接"
            }
            return
        }

        if process.isRunning {
            process.terminate()
        }

        self.process = nil
        cleanupAfterProcess()
        if resetState {
            state = .idle
            detail = "已断开连接"
        }
    }

    private var shouldReconnect: Bool {
        autoReconnectEnabled
            && !manualStopRequested
            && lastRequest != nil
            && reconnectAttempt < maxReconnectAttempts
    }

    private func scheduleReconnect(reason: String) {
        guard let lastRequest else {
            fail(reason)
            return
        }

        reconnectAttempt += 1
        let delay: UInt64 = switch reconnectAttempt {
        case 1: 3
        case 2: 8
        default: 15
        }

        state = .connecting
        detail = networkAvailable
            ? "连接中断，\(delay) 秒后自动重连（\(reconnectAttempt)/\(maxReconnectAttempts)）。"
            : "连接中断，网络不可用，自动重连已暂停（\(reconnectAttempt)/\(maxReconnectAttempts)）。"

        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.autoReconnectEnabled else { return }
            await self.waitForNetworkIfNeeded()
            guard !Task.isCancelled, self.autoReconnectEnabled else { return }
            self.start(lastRequest, autoReconnect: true, resetReconnectAttempts: false)
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        detail = message
    }

    private func appendLog(_ text: String) {
        logBuffer += text
        if logBuffer.count > 8_000 {
            logBuffer = String(logBuffer.suffix(8_000))
        }
        if !hasLog, !logBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasLog = true
        }

        guard logPublishingEnabled else { return }

        guard logPublishTask == nil else { return }
        logPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.flushLog()
        }
    }

    private func clearLog() {
        logPublishTask?.cancel()
        logPublishTask = nil
        logBuffer = ""
        log = ""
        hasLog = false
    }

    private func flushLog() {
        logPublishTask?.cancel()
        logPublishTask = nil
        if log != logBuffer {
            log = logBuffer
        }
    }

    private func updateNetworkAvailability(_ isAvailable: Bool) {
        networkAvailable = isAvailable
        guard isAvailable else { return }

        let waiters = networkWaiters
        networkWaiters.removeAll()
        waiters.forEach { $0.continuation.resume() }

        if case .connecting = state, autoReconnectEnabled, reconnectAttempt > 0 {
            detail = "网络已恢复，正在继续自动重连（\(reconnectAttempt)/\(maxReconnectAttempts)）..."
        }
    }

    private func waitForNetworkIfNeeded() async {
        guard !networkAvailable else { return }

        detail = "网络不可用，自动重连已暂停。网络恢复后将继续连接。"
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                networkWaiters.append(NetworkWaiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeNetworkWaiter(id: waiterID)
            }
        }
    }

    private func resumeNetworkWaiter(id: UUID) {
        guard let index = networkWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = networkWaiters.remove(at: index)
        waiter.continuation.resume()
    }

    private func messageForTerminatedProcess(_ process: Process) -> String {
        let base = process.terminationStatus == 0
            ? "SSH 连接已结束。"
            : "SSH 连接失败，退出码 \(process.terminationStatus)。"

        let trimmedLog = logBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLog.isEmpty else { return base }
        return "\(base)\n\(trimmedLog)"
    }

    private func makeAskPassScript() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHocks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scriptURL = directory.appendingPathComponent("ssh-askpass-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$SSHOCKS_ASKPASS_SECRET"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func cleanupAfterProcess() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        stdoutPipe = nil

        if let askPassScriptURL {
            try? FileManager.default.removeItem(at: askPassScriptURL)
            self.askPassScriptURL = nil
        }
    }

    deinit {
        pathMonitor.cancel()
        logPublishTask?.cancel()
        reconnectTask?.cancel()
        networkWaiters.forEach { $0.continuation.resume() }
        networkWaiters.removeAll()
        process?.terminate()
        try? askPassScriptURL.map(FileManager.default.removeItem)
    }
}
