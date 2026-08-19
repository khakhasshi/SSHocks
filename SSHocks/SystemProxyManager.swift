//
//  SystemProxyManager.swift
//  SSHocks
//
//  Created by Codex on 17/6/2026.
//

import Combine
import Foundation

@MainActor
final class SystemProxyManager: ObservableObject {
    @Published private(set) var services: [String] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var detail = "尚未读取系统代理状态"
    @Published private(set) var isWorking = false

    func loadServices() async {
        isWorking = true
        let result = await Self.runNetworkSetup(arguments: ["-listallnetworkservices"])
        isWorking = false

        guard result.exitCode == 0 else {
            detail = "读取网络服务失败：\(result.output)"
            return
        }

        services = result.output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .map { service in
                service.hasPrefix("*") ? String(service.dropFirst()) : service
            }
            .filter { !$0.isEmpty }
    }

    func refresh(service: String) async {
        guard !service.isEmpty else {
            detail = "请选择网络服务。"
            isEnabled = false
            return
        }

        let result = await Self.runNetworkSetup(arguments: ["-getsocksfirewallproxy", service])
        guard result.exitCode == 0 else {
            detail = "读取 \(service) 的 SOCKS5 状态失败：\(result.output)"
            isEnabled = false
            return
        }

        isEnabled = result.output.contains("Enabled: Yes")
        detail = isEnabled
            ? "\(service) 已启用系统 SOCKS5 代理。"
            : "\(service) 未启用系统 SOCKS5 代理。"
    }

    func enable(service: String, port: Int) async {
        guard !service.isEmpty else {
            detail = "请选择网络服务。"
            return
        }

        guard (1...65535).contains(port) else {
            detail = "系统代理端口必须在 1 到 65535 之间。"
            return
        }

        isWorking = true
        let setProxy = await Self.runNetworkSetup(
            arguments: ["-setsocksfirewallproxy", service, "127.0.0.1", "\(port)"]
        )
        guard setProxy.exitCode == 0 else {
            isWorking = false
            detail = "写入 \(service) 系统代理失败：\(setProxy.output)"
            return
        }

        let enableProxy = await Self.runNetworkSetup(arguments: ["-setsocksfirewallproxystate", service, "on"])
        isWorking = false

        guard enableProxy.exitCode == 0 else {
            detail = "启用 \(service) 系统代理失败：\(enableProxy.output)"
            return
        }

        isEnabled = true
        detail = "\(service) 已切到 SOCKS5 127.0.0.1:\(port)。"
    }

    func disable(service: String) async {
        guard !service.isEmpty else {
            detail = "请选择网络服务。"
            return
        }

        isWorking = true
        let result = await Self.runNetworkSetup(arguments: ["-setsocksfirewallproxystate", service, "off"])
        isWorking = false

        guard result.exitCode == 0 else {
            detail = "关闭 \(service) 系统代理失败：\(result.output)"
            return
        }

        isEnabled = false
        detail = "\(service) 的系统 SOCKS5 代理已关闭。"
    }

    private nonisolated static func runNetworkSetup(arguments: [String]) async -> (exitCode: Int32, output: String) {
        await Task.detached(priority: .utility) {
            let path = "/usr/sbin/networksetup"
            guard FileManager.default.isExecutableFile(atPath: path) else {
                return (127, "\(path) 不存在或不可执行。")
            }

            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                return (process.terminationStatus, output + error)
            } catch {
                return (126, error.localizedDescription)
            }
        }.value
    }
}
