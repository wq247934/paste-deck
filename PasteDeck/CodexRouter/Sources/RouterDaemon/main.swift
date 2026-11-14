//
//  main.swift
//  pastedeck-codex-router
//
//  Codex 模型路由守护进程：独立于 PasteDeck 主程序运行。
//  仅监听 127.0.0.1；不记录任何凭据；日志走 stderr + router.log。
//
//  独立恢复模式（PasteDeck 不可用时的命令行兜底）：
//    pastedeck-codex-router --restore [--codex-home <path>] [--state-dir <path>]
//  行为：停止守护进程残留 → 外科手术式移除 config.toml 托管块并恢复
//  model_provider → 清理孤立状态文件与凭据物化文件（端点配置保留）。
//

import Foundation
import CodexRouterKit

let arguments = Array(CommandLine.arguments.dropFirst())
var stateDirectory = CodexRouterConstants.stateDirectory()
var requestedPort = CodexRouterConstants.defaultPort
var restoreRequested = false
var codexHomeOverride: String?

var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--state-dir" where index + 1 < arguments.count:
        index += 1
        stateDirectory = URL(fileURLWithPath: arguments[index])
    case "--codex-home" where index + 1 < arguments.count:
        index += 1
        codexHomeOverride = arguments[index]
    case "--port" where index + 1 < arguments.count:
        index += 1
        requestedPort = Int(arguments[index]) ?? CodexRouterConstants.defaultPort
    case "--restore":
        restoreRequested = true
    case "--help", "-h":
        print("""
        用法：
          pastedeck-codex-router [--state-dir <dir>] [--port <n>]
              启动路由守护进程（默认状态目录 ~/.codex/pastedeck-router，端口 4212）
          pastedeck-codex-router --restore [--codex-home <dir>] [--state-dir <dir>]
              恢复 Codex 原生配置：移除托管块、恢复 model_provider、清理守护进程残留
        """)
        exit(0)
    default:
        break
    }
    index += 1
}

if restoreRequested {
    let controller = CodexRouterController(stateDirectory: stateDirectory, codexHome: codexHomeOverride)
    do {
        // 先停守护进程残留，再恢复配置。
        controller.stopDaemon()
        let report = try controller.restore()
        FileHandle.standardError.write(Data("[pastedeck-codex-router] 恢复完成：\(report)\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("[pastedeck-codex-router] 恢复失败：\(error.localizedDescription)\n".utf8))
        exit(2)
    }
}

let service = RouterService(stateDirectory: stateDirectory, port: UInt16(requestedPort))
if service.start() {
    // 常驻：RunLoop 阻塞主线程（线程模型由各组件自持）。
    // 守护进程没有 UI；signal 处理由 stop() 的管理端点/kill 完成。
    RunLoop.main.run()
} else {
    exit(1)
}
