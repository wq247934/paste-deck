//
//  DaemonLauncher.swift
//  PasteDeck
//
//  守护进程二进制定位与启动。启动后与主程序解耦：
//  PasteDeck 退出不影响 Codex 请求转发。
//

import Foundation

enum DaemonLauncher {

    /// 守护进程二进制候选路径（按优先级）。
    static func locateDaemonBinary() -> String? {
        var candidates: [String] = []
        if let mainURL = Bundle.main.executableURL {
            let directory = mainURL.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("pastedeck-codex-router").path)
            // .app 包内的 Resources 布局。
            candidates.append(Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/pastedeck-codex-router").path)
            // swift run / swift build 开发布局（同目录上一级）。
            candidates.append(directory.deletingLastPathComponent()
                .appendingPathComponent("pastedeck-codex-router").path)
        }
        // 源码树开发布局。
        candidates.append(NSHomeDirectory() + "/Documents/go-project/paste-deck/.build/debug/pastedeck-codex-router")
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 启动守护进程（ detached；日志重定向到 stateDir/router.log）。
    static func launch(stateDirectory: URL, port: Int) throws -> Process {
        guard let binary = locateDaemonBinary() else {
            throw RouterControllerError.daemonBinaryMissing
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "--state-dir", stateDirectory.path,
            "--port", String(port),
        ]
        let logPath = stateDirectory.appendingPathComponent("router.log")
        if !FileManager.default.fileExists(atPath: logPath.path) {
            FileManager.default.createFile(atPath: logPath.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        process.standardOutput = try FileHandle(forWritingTo: logPath)
        process.standardError = try FileHandle(forWritingTo: logPath)
        process.qualityOfService = .utility
        try process.run()
        // 父进程退出后子进程继续运行（detach 由调用方不 wait 保证）。
        return process
    }
}
