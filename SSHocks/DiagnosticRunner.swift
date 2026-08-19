//
//  DiagnosticRunner.swift
//  SSHocks
//
//  Created by Codex on 17/6/2026.
//

import Foundation

enum DiagnosticRunner {
    nonisolated static func run(
        host: String,
        sshPort: Int,
        localPort: Int,
        tunnelRunning: Bool
    ) async -> String {
        await Task.detached(priority: .utility) {
            var report = [String]()
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

            report.append("SSHocks 诊断报告")
            report.append("时间：\(Date().formatted(date: .numeric, time: .standard))")
            report.append("")

            let sshVersion = runCommand("/usr/bin/ssh", arguments: ["-V"])
            report.append(section(
                title: "系统 ssh",
                ok: sshVersion.exitCode == 0,
                detail: sshVersion.output.isEmpty ? "未找到 /usr/bin/ssh。" : sshVersion.output
            ))

            let lsof = runCommand(
                "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP:\(localPort)", "-sTCP:LISTEN"]
            )
            let lsofOutput = lsof.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if lsofOutput.isEmpty {
                report.append(section(
                    title: "本地端口 127.0.0.1:\(localPort)",
                    ok: !tunnelRunning,
                    detail: tunnelRunning
                        ? "应用认为隧道正在运行，但没有发现监听进程。可以断开后重新连接。"
                        : "端口空闲，可以用于 SOCKS5 监听。"
                ))
            } else {
                report.append(section(
                    title: "本地端口 127.0.0.1:\(localPort)",
                    ok: tunnelRunning,
                    detail: lsofOutput
                ))
            }

            if trimmedHost.isEmpty {
                report.append(section(
                    title: "SSH 服务器可达性",
                    ok: false,
                    detail: "未填写服务器地址，跳过远端端口检测。"
                ))
            } else {
                let nc = runCommand(
                    "/usr/bin/nc",
                    arguments: ["-G", "4", "-z", trimmedHost, "\(sshPort)"]
                )
                report.append(section(
                    title: "SSH 服务器可达性",
                    ok: nc.exitCode == 0,
                    detail: nc.exitCode == 0
                        ? "\(trimmedHost):\(sshPort) 可以建立 TCP 连接。"
                        : "无法连接 \(trimmedHost):\(sshPort)。\n\(nc.output)"
                ))
            }

            if tunnelRunning {
                let curl = runCommand(
                    "/usr/bin/curl",
                    arguments: [
                        "--socks5-hostname", "127.0.0.1:\(localPort)",
                        "--max-time", "8",
                        "-I",
                        "https://www.apple.com"
                    ]
                )
                report.append(section(
                    title: "SOCKS5 出口测试",
                    ok: curl.exitCode == 0,
                    detail: curl.exitCode == 0
                        ? firstLines(curl.output, limit: 8)
                        : "通过本地 SOCKS5 访问测试站点失败。\n\(curl.output)"
                ))
            } else {
                report.append(section(
                    title: "SOCKS5 出口测试",
                    ok: false,
                    detail: "隧道未运行，跳过出口测试。"
                ))
            }

            return report.joined(separator: "\n\n")
        }.value
    }

    private nonisolated static func section(title: String, ok: Bool, detail: String) -> String {
        """
        [\(ok ? "OK" : "检查")] \(title)
        \(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private nonisolated static func firstLines(_ text: String, limit: Int) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .prefix(limit)
            .joined(separator: "\n")
    }

    private nonisolated static func runCommand(_ path: String, arguments: [String]) -> (exitCode: Int32, output: String) {
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
    }
}
