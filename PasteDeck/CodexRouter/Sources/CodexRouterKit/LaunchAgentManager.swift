//
//  LaunchAgentManager.swift
//  PasteDeck
//
//  用户级 LaunchAgent 托管路由守护进程：
//  - 登录自动启动（RunAtLoad）；
//  - 异常退出自动拉起（KeepAlive）；
//  - 一键关闭/恢复时注销并移除 plist。
//  不需要任何常驻管理程序；守护进程本身保持无状态。
//

import Foundation

public struct LaunchAgentManager {
    public static let label = "com.pastedeck.codex-router"

    let launchAgentsDirectory: URL
    /// launchctl 注入点（测试用）；参数为 (子命令数组)。
    let runner: ([String]) throws -> Void

    public init(
        launchAgentsDirectory: URL? = nil,
        runner: (([String]) throws -> Void)? = nil
    ) {
        let home = NSHomeDirectory()
        self.launchAgentsDirectory = launchAgentsDirectory
            ?? URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        if let runner {
            self.runner = runner
        } else {
            self.runner = { arguments in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "launchctl", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey:
                                    "launchctl \(arguments.first ?? "") 退出码 \(process.terminationStatus)"])
                }
            }
        }
    }

    public var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
    }

    public func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 注册 Agent 并加载（bootout 旧定义后 bootstrap）。
    public func install(daemonPath: String, stateDirectory: URL, port: Int, logPath: URL) throws {
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        let plist = Self.plistContent(
            label: Self.label,
            daemonPath: daemonPath,
            stateDirectory: stateDirectory,
            port: port,
            logPath: logPath
        )
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        let guiTarget = "gui/\(getuid())"
        // 已加载的旧定义先卸载（未加载时 bootout 报错，忽略）。
        try? runner(["bootout", "\(guiTarget)/\(Self.label)"])
        do {
            try runner(["bootstrap", guiTarget, plistURL.path])
        } catch {
            throw RouterControllerError.daemonStartFailed(port: port)
        }
    }

    /// 注销并删除 plist；未加载时静默完成。
    public func uninstall() {
        let guiTarget = "gui/\(getuid())"
        try? runner(["bootout", "\(guiTarget)/\(Self.label)"])
        try? FileManager.default.removeItem(atPath: plistURL.path)
    }

    static func plistContent(label: String, daemonPath: String, stateDirectory: URL, port: Int, logPath: URL) -> String {
        let escapedDaemon = daemonPath.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let escapedState = stateDirectory.path.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        let escapedLog = logPath.path.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(escapedDaemon)</string>
                <string>--state-dir</string>
                <string>\(escapedState)</string>
                <string>--port</string>
                <string>\(port)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>StandardOutPath</key>
            <string>\(escapedLog)</string>
            <key>StandardErrorPath</key>
            <string>\(escapedLog)</string>
        </dict>
        </plist>
        """
    }
}
