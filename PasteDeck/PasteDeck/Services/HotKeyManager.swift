//
//  HotKeyManager.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit

class HotKeyManager {
    private var eventMonitor: Any?
    private var hotKeyCallback: (() -> Void)?
    private var isRegistered = false

    init() {
        print("HotKeyManager: 初始化")
    }

    deinit {
        unregister()
    }

    func registerHotKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        unregister()
        hotKeyCallback = callback

        // 检查辅助功能权限
        let trusted = AXIsProcessTrusted()
        print("HotKeyManager: 辅助功能权限 = \(trusted)")

        if !trusted {
            print("HotKeyManager: 没有辅助功能权限，无法注册全局快捷键")
            // 请求权限
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            return
        }

        // 使用 NSEvent 全局监听
        let expectedModifiers = modifiers
        let expectedKeyCode = keyCode

        print("HotKeyManager: 注册快捷键 keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 检查修饰键
            let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let eventKeyCode = event.keyCode

            // 打印调试信息
            if eventKeyCode == expectedKeyCode {
                print("HotKeyManager: 检测到 V 键按下")
                print("  - 期望修饰键: \(expectedModifiers.rawValue)")
                print("  - 实际修饰键: \(eventModifiers.rawValue)")
                print("  - 匹配: \(eventModifiers == expectedModifiers)")
            }

            if eventKeyCode == expectedKeyCode && eventModifiers == expectedModifiers {
                print("HotKeyManager: 快捷键匹配，执行回调")
                DispatchQueue.main.async {
                    self?.hotKeyCallback?()
                }
            }
        }

        isRegistered = true
        print("HotKeyManager: 快捷键注册成功")
    }

    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            isRegistered = false
            print("HotKeyManager: 快捷键已注销")
        }
    }

    func isHotKeyRegistered() -> Bool {
        return isRegistered
    }
}
