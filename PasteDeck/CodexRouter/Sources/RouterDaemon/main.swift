//
//  main.swift
//  pastedeck-codex-router
//
//  Codex 模型路由守护进程：独立于 PasteDeck 主程序运行。
//  仅监听 127.0.0.1；不记录任何凭据；日志走 stderr + router.log。
//

import Foundation
import CodexRouterKit

let arguments = Array(CommandLine.arguments.dropFirst())
var stateDirectory = CodexRouterConstants.stateDirectory()
var requestedPort = CodexRouterConstants.defaultPort

var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--state-dir" where index + 1 < arguments.count:
        index += 1
        stateDirectory = URL(fileURLWithPath: arguments[index])
    case "--port" where index + 1 < arguments.count:
        index += 1
        requestedPort = Int(arguments[index]) ?? CodexRouterConstants.defaultPort
    default:
        break
    }
    index += 1
}

let service = RouterService(stateDirectory: stateDirectory, port: UInt16(requestedPort))
if service.start() {
    // 常驻：RunLoop 阻塞主线程（线程模型由各组件自持）。
    // 守护进程没有 UI；signal 处理由 stop() 的管理端点/kill 完成。
    RunLoop.main.run()
} else {
    exit(1)
}
