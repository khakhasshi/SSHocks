//
//  SSHocksApp.swift
//  SSHocks
//
//  Created by JIANGJINGZHE on 17/6/2026.
//

import AppKit
import SwiftUI

final class SSHocksAppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }
}

@main
struct SSHocksApp: App {
    @NSApplicationDelegateAdaptor(SSHocksAppDelegate.self) private var appDelegate

    @StateObject private var tunnelManager = SSHTunnelManager()
    @StateObject private var systemProxyManager = SystemProxyManager()
    @StateObject private var healthMonitor = ProxyHealthMonitor()
    @StateObject private var tunModeManager = TUNModeManager()

    var body: some Scene {
        WindowGroup("SSHocks", id: "main") {
            ContentView(
                tunnelManager: tunnelManager,
                systemProxyManager: systemProxyManager,
                healthMonitor: healthMonitor,
                tunModeManager: tunModeManager
            )
            .onAppear {
                appDelegate.onTerminate = {
                    tunnelManager.shutdownForTermination()
                    tunModeManager.shutdownForTermination()
                }
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            SSHocksMenuBarView(
                tunnelManager: tunnelManager,
                statusSummary: tunnelManager.statusSummary,
                systemProxyManager: systemProxyManager,
                tunModeManager: tunModeManager
            )
        } label: {
            SSHocksMenuBarLabel(statusSummary: tunnelManager.statusSummary)
        }
        .menuBarExtraStyle(.menu)
    }
}
