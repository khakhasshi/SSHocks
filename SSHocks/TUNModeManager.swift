//
//  TUNModeManager.swift
//  SSHocks
//
//  Created by Codex on 17/6/2026.
//

import Combine
import Foundation

enum TUNModeState: Equatable {
    case idle
    case unavailable
    case enabling
    case enabled
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "未开启"
        case .unavailable:
            return "不可用"
        case .enabling:
            return "开启中"
        case .enabled:
            return "已开启"
        case .failed:
            return "开启失败"
        }
    }

    var symbol: String {
        switch self {
        case .idle:
            return "circle"
        case .unavailable:
            return "exclamationmark.triangle"
        case .enabling:
            return "arrow.triangle.2.circlepath"
        case .enabled:
            return "network"
        case .failed:
            return "xmark.octagon"
        }
    }
}

@MainActor
final class TUNModeManager: ObservableObject {
    @Published private(set) var state: TUNModeState = .idle
    @Published private(set) var detail = "TUN 模式未开启。"
    @Published private(set) var enginePath: String?
    @Published private(set) var log = ""
    @Published private(set) var isInstallingPackage = false

    private var process: Process?
    private var configURL: URL?
    private var privilegedLogURL: URL?
    private var privilegedPID: Int32?
    private var monitorTask: Task<Void, Never>?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var userRequestedStop = false

    var isEnabled: Bool {
        state == .enabled || state == .enabling
    }

    func refreshAvailability() {
        enginePath = findSingBoxPath()
        if let enginePath {
            if state == .unavailable {
                state = .idle
            }
            detail = "已检测到 TUN 引擎：\(enginePath)"
        } else {
            state = .unavailable
            detail = "未检测到 TUN 引擎。请安装 sing-box，或后续将 sing-box 放入 App Bundle。"
        }
    }

    @discardableResult
    func installEnginePackage() async -> Bool {
        guard !isInstallingPackage else { return false }

        guard let brewPath = findBrewPath() else {
            state = .unavailable
            detail = "未检测到 Homebrew。请先安装 Homebrew，或手动将 sing-box 放入 /opt/homebrew/bin、/usr/local/bin 或 App Bundle。"
            return false
        }

        isInstallingPackage = true
        log = ""
        state = .unavailable
        detail = "正在通过 Homebrew 安装 TUN 套件 sing-box..."

        let result = await Self.runProcess(executable: brewPath, arguments: ["install", "sing-box"])
        isInstallingPackage = false
        appendLog(result.output)

        guard result.status == 0 else {
            state = .failed("套件安装失败。")
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            detail = message.isEmpty ? "Homebrew 安装 sing-box 失败，退出码 \(result.status)。" : message
            return false
        }

        refreshAvailability()
        if enginePath != nil {
            detail = "TUN 套件已安装完成，并检测到 sing-box。"
            return true
        }

        state = .unavailable
        detail = "安装命令已完成，但仍未检测到 sing-box。请检查 Homebrew 输出或重新检测引擎。"
        return false
    }

    @discardableResult
    func enable(localPort: Int, tunnelRunning: Bool) async -> Bool {
        guard tunnelRunning else {
            state = .failed("需要先启动 SSH SOCKS5 隧道。")
            detail = "TUN 模式需要先有可用的本地 SOCKS5 出口。"
            return false
        }

        guard (1...65535).contains(localPort) else {
            state = .failed("端口无效。")
            detail = "本地 SOCKS5 端口必须在 1 到 65535 之间。"
            return false
        }

        if enginePath == nil {
            refreshAvailability()
        }

        guard let enginePath else {
            return false
        }

        disable(resetDetail: false)

        do {
            let resources = try makeSingBoxResources(localPort: localPort)
            let configURL = resources.configURL
            let logURL = resources.logURL
            self.configURL = configURL
            self.privilegedLogURL = logURL
            userRequestedStop = false
            log = ""
            state = .enabling
            detail = "TUN 模式需要管理员权限配置 macOS 网络接口。请在系统弹窗中授权..."

            let launchResult = await Self.launchPrivilegedSingBox(
                enginePath: enginePath,
                configPath: configURL.path,
                logPath: logURL.path
            )

            refreshPrivilegedLog()

            guard launchResult.status == 0 else {
                cleanup()
                state = .failed("管理员授权或启动失败。")
                let message = launchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                detail = message.isEmpty ? "未能以管理员权限启动 TUN 引擎。" : message
                return false
            }

            guard let pid = Int32(launchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                cleanup()
                state = .failed("无法读取 TUN 引擎 PID。")
                detail = "TUN 引擎启动命令未返回有效 PID：\(launchResult.output)"
                return false
            }

            privilegedPID = pid

            try? await Task.sleep(for: .seconds(1.5))
            refreshPrivilegedLog()

            guard await Self.isProcessRunning(pid: pid) else {
                let message = log.trimmingCharacters(in: .whitespacesAndNewlines)
                cleanup()
                state = .failed("TUN 引擎未能保持运行。")
                detail = message.isEmpty
                    ? "TUN 引擎启动后立即退出。"
                    : message
                return false
            }

            state = .enabled
            detail = "TUN 模式已开启，所有可路由流量将尝试经由 SOCKS5 127.0.0.1:\(localPort)。"
            startPrivilegedMonitor(pid: pid)
            return true
        } catch {
            cleanup()
            state = .failed(error.localizedDescription)
            detail = "无法启动 TUN 模式：\(error.localizedDescription)"
            return false
        }
    }

    func disable(resetDetail: Bool = true) {
        userRequestedStop = true

        if let process, process.isRunning {
            process.terminate()
        }

        if let privilegedPID {
            Task {
                _ = await Self.killPrivilegedProcess(pid: privilegedPID)
            }
        }

        cleanup()

        if resetDetail {
            state = .idle
            detail = "TUN 模式已关闭。"
        }
    }

    func shutdownForTermination() {
        userRequestedStop = true
        monitorTask?.cancel()
        monitorTask = nil

        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        if let privilegedPID {
            _ = Self.killPrivilegedProcessSync(pid: privilegedPID)
        }

        cleanup()
        state = .idle
        detail = "TUN 模式已关闭。"
    }

    private func makeSingBoxResources(localPort: Int) throws -> (configURL: URL, logURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHocks/TUN", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let configURL = directory.appendingPathComponent("sing-box-\(id).json")
        let logURL = directory.appendingPathComponent("sing-box-\(id).log")
        let config = """
        {
          "log": {
            "level": "warn"
          },
          "inbounds": [
            {
              "type": "tun",
              "tag": "sshocks-tun",
              "address": [
                "172.19.0.1/30"
              ],
              "auto_route": true,
              "strict_route": false,
              "stack": "system"
            }
          ],
          "outbounds": [
            {
              "type": "socks",
              "tag": "sshocks-socks",
              "server": "127.0.0.1",
              "server_port": \(localPort),
              "version": "5"
            }
          ]
        }
        """

        try config.write(to: configURL, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        return (configURL, logURL)
    }

    private func cleanup() {
        monitorTask?.cancel()
        monitorTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        process = nil
        privilegedPID = nil

        if let configURL {
            try? FileManager.default.removeItem(at: configURL)
            self.configURL = nil
        }
        if let privilegedLogURL {
            try? FileManager.default.removeItem(at: privilegedLogURL)
            self.privilegedLogURL = nil
        }
    }

    private func appendLog(_ text: String) {
        log += text
        if log.count > 8_000 {
            log = String(log.suffix(8_000))
        }
    }

    private func refreshPrivilegedLog() {
        guard
            let privilegedLogURL,
            let text = try? String(contentsOf: privilegedLogURL, encoding: .utf8),
            !text.isEmpty
        else {
            return
        }

        log = text.count > 8_000 ? String(text.suffix(8_000)) : text
    }

    private func startPrivilegedMonitor(pid: Int32) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refreshPrivilegedLog()

                let isRunning = await Self.isProcessRunning(pid: pid)
                guard !Task.isCancelled, !isRunning else { continue }

                let message = self.log.trimmingCharacters(in: .whitespacesAndNewlines)
                self.cleanup()

                if self.userRequestedStop {
                    self.state = .idle
                    self.detail = "TUN 模式已关闭。"
                } else {
                    self.state = .failed("sing-box 已退出。")
                    self.detail = message.isEmpty ? "TUN 引擎已退出。" : message
                }
                return
            }
        }
    }

    private func findSingBoxPath() -> String? {
        let candidates = [
            Bundle.main.url(forResource: "sing-box", withExtension: nil)?.path,
            "/opt/homebrew/bin/sing-box",
            "/usr/local/bin/sing-box",
            "/usr/bin/sing-box"
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func findBrewPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private struct ProcessResult: Sendable {
        let status: Int32
        let output: String
    }

    private nonisolated static func launchPrivilegedSingBox(
        enginePath: String,
        configPath: String,
        logPath: String
    ) async -> ProcessResult {
        let command = [
            "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "\(enginePath.shellQuoted) run -c \(configPath.shellQuoted) > \(logPath.shellQuoted) 2>&1 & echo $!"
        ].joined(separator: "; ")

        return await runProcess(
            executable: "/usr/bin/osascript",
            arguments: [
                "-e",
                "do shell script \(command.appleScriptStringLiteral) with administrator privileges"
            ]
        )
    }

    private nonisolated static func killPrivilegedProcess(pid: Int32) async -> ProcessResult {
        let command = "/bin/kill \(pid) 2>/dev/null || true"
        return await runProcess(
            executable: "/usr/bin/osascript",
            arguments: [
                "-e",
                "do shell script \(command.appleScriptStringLiteral) with administrator privileges"
            ]
        )
    }

    private nonisolated static func killPrivilegedProcessSync(pid: Int32) -> ProcessResult {
        let command = "/bin/kill \(pid) 2>/dev/null || true"
        return runProcessSync(
            executable: "/usr/bin/osascript",
            arguments: [
                "-e",
                "do shell script \(command.appleScriptStringLiteral) with administrator privileges"
            ]
        )
    }

    private nonisolated static func isProcessRunning(pid: Int32) async -> Bool {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-p", "\(pid)", "-o", "pid="]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    private nonisolated static func runProcess(executable: String, arguments: [String]) async -> ProcessResult {
        await Task.detached(priority: .userInitiated) {
            let logURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SSHocks/TUN/install-\(UUID().uuidString).log")

            do {
                try FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                let logHandle = try FileHandle(forWritingTo: logURL)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.standardOutput = logHandle
                process.standardError = logHandle
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                ]) { current, _ in current }

                try process.run()
                process.waitUntilExit()
                try? logHandle.close()

                let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: logURL)
                return ProcessResult(status: process.terminationStatus, output: output)
            } catch {
                let output = "无法执行安装命令：\(error.localizedDescription)"
                try? FileManager.default.removeItem(at: logURL)
                return ProcessResult(status: -1, output: output)
            }
        }.value
    }

    private nonisolated static func runProcessSync(executable: String, arguments: [String]) -> ProcessResult {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]) { current, _ in current }

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ProcessResult(status: process.terminationStatus, output: output)
        } catch {
            return ProcessResult(status: -1, output: "无法执行命令：\(error.localizedDescription)")
        }
    }

    deinit {
        process?.terminate()
        if let privilegedPID {
            Task {
                _ = await Self.killPrivilegedProcess(pid: privilegedPID)
            }
        }
        try? configURL.map(FileManager.default.removeItem)
        try? privilegedLogURL.map(FileManager.default.removeItem)
    }
}

private extension String {
    nonisolated var shellQuoted: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    nonisolated var appleScriptStringLiteral: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
