//
//  ProxyHealthMonitor.swift
//  SSHocks
//
//  Created by Codex on 17/6/2026.
//

import Combine
import Foundation
import AppKit
import Network
import SwiftUI

enum ProxyHealthState: Equatable {
    case idle
    case checking
    case healthy(Int)
    case degraded(String)

    var title: String {
        switch self {
        case .idle:
            return "未检测"
        case .checking:
            return "检测中"
        case .healthy(let latency):
            return "健康 \(latency) ms"
        case .degraded:
            return "不可用"
        }
    }

    var symbol: String {
        switch self {
        case .idle:
            return "circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .healthy:
            return "checkmark.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .checking:
            return .orange
        case .healthy:
            return .green
        case .degraded:
            return .red
        }
    }
}

@MainActor
final class ProxyHealthMonitor: ObservableObject {
    @Published private(set) var state: ProxyHealthState = .idle
    @Published private(set) var detail = "隧道未运行，尚未检测。"
    @Published private(set) var lastCheckedAt: Date?

    private var monitorTask: Task<Void, Never>?
    private var consecutiveHealthyChecks = 0
    private var isChecking = false
    private var isAppActive = true
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var didResignActiveObserver: NSObjectProtocol?

    init() {
        isAppActive = NSApplication.shared.isActive
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isAppActive = true
            }
        }
        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isAppActive = false
            }
        }
    }

    func start(port: Int) {
        stop()
        consecutiveHealthyChecks = 0
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkNow(port: port)
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.nextCheckIntervalSeconds()))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        consecutiveHealthyChecks = 0
        state = .idle
        detail = "隧道未运行，尚未检测。"
        lastCheckedAt = nil
    }

    func checkNow(port: Int) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard (1...65535).contains(port) else {
            consecutiveHealthyChecks = 0
            state = .degraded("端口无效")
            detail = "本地 SOCKS5 端口必须在 1 到 65535 之间。"
            lastCheckedAt = Date()
            return
        }

        state = .checking
        detail = "正在检查 127.0.0.1:\(port) 和 SOCKS5 出口..."

        let result = await Self.runCheck(port: port)
        lastCheckedAt = Date()

        if result.ok {
            consecutiveHealthyChecks += 1
            state = .healthy(result.latencyMS)
            detail = "SOCKS5 出口可用，延迟约 \(result.latencyMS) ms。"
        } else {
            consecutiveHealthyChecks = 0
            state = .degraded(result.message)
            detail = result.message
        }
    }

    private func nextCheckIntervalSeconds() -> UInt64 {
        let baseInterval: UInt64 = switch state {
        case .healthy where consecutiveHealthyChecks >= 3:
            90
        case .healthy:
            20
        case .degraded:
            35
        case .checking, .idle:
            15
        }

        return isAppActive ? baseInterval : max(baseInterval, 180)
    }

    private nonisolated static func runCheck(port: Int) async -> (ok: Bool, latencyMS: Int, message: String) {
        await Task.detached(priority: .utility) {
            let startedAt = Date()
            let result = SOCKS5Probe.run(localPort: port)
            let latency = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))

            return result.ok
                ? (true, latency, "OK")
                : (false, latency, result.message)
        }.value
    }

    deinit {
        monitorTask?.cancel()
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        if let didResignActiveObserver {
            NotificationCenter.default.removeObserver(didResignActiveObserver)
        }
    }
}

private enum SOCKS5Probe {
    nonisolated static func run(localPort: Int) -> (ok: Bool, message: String) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(localPort)) else {
            return (false, "本地 SOCKS5 端口必须在 1 到 65535 之间。")
        }

        let queue = DispatchQueue(label: "SSHocks.SOCKS5Probe", qos: .utility)
        let timeout: TimeInterval = 6
        let connection = NWConnection(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: port,
            using: .tcp
        )
        defer { connection.cancel() }

        guard waitUntilReady(connection, queue: queue, timeout: timeout) else {
            return (false, "本地 SOCKS5 端口 127.0.0.1:\(localPort) 未监听或无响应。")
        }

        guard send(Data([0x05, 0x01, 0x00]), on: connection, timeout: timeout) else {
            return (false, "SOCKS5 握手发送失败。")
        }

        guard let greeting = receive(minimum: 2, maximum: 2, on: connection, timeout: timeout), greeting.count == 2 else {
            return (false, "SOCKS5 握手无响应。")
        }

        guard greeting[greeting.startIndex] == 0x05, greeting[greeting.index(after: greeting.startIndex)] == 0x00 else {
            return (false, "SOCKS5 代理未接受无密码认证。")
        }

        guard send(connectRequest(host: "www.apple.com", port: 443), on: connection, timeout: timeout) else {
            return (false, "SOCKS5 出口请求发送失败。")
        }

        guard let response = receive(minimum: 5, maximum: 262, on: connection, timeout: timeout), response.count >= 2 else {
            return (false, "SOCKS5 出口请求无响应。")
        }

        let version = response[response.startIndex]
        let status = response[response.index(after: response.startIndex)]
        guard version == 0x05, status == 0x00 else {
            return (false, "SOCKS5 出口连接失败，状态码 0x\(String(status, radix: 16))。")
        }

        return (true, "OK")
    }

    private nonisolated static func waitUntilReady(_ connection: NWConnection, queue: DispatchQueue, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        nonisolated(unsafe) var isReady = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                lock.withLock { isReady = true }
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)

        _ = semaphore.wait(timeout: .now() + timeout)
        return lock.withLock { isReady }
    }

    private nonisolated static func send(_ data: Data, on connection: NWConnection, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var didSend = false

        connection.send(content: data, completion: .contentProcessed { error in
            lock.withLock { didSend = error == nil }
            semaphore.signal()
        })

        _ = semaphore.wait(timeout: .now() + timeout)
        return lock.withLock { didSend }
    }

    private nonisolated static func receive(minimum: Int, maximum: Int, on connection: NWConnection, timeout: TimeInterval) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var receivedData: Data?

        connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, _, _ in
            lock.withLock { receivedData = data }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + timeout)
        return lock.withLock { receivedData }
    }

    private nonisolated static func connectRequest(host: String, port: UInt16) -> Data {
        var data = Data([0x05, 0x01, 0x00, 0x03, UInt8(host.utf8.count)])
        data.append(contentsOf: host.utf8)
        data.append(UInt8(port >> 8))
        data.append(UInt8(port & 0x00ff))
        return data
    }
}

private extension NSLock {
    nonisolated func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
