//
//  HotKeyManager.swift
//  PasteDeck
//
//  Manages global hotkey registration using NSEvent monitoring.
//  Requires accessibility permission for global key event capture.
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit

/// Manages global hotkey registration and handling
class HotKeyManager {
    private var eventMonitor: Any?
    private var hotKeyCallback: (() -> Void)?
    private var isRegistered = false

    /// 保存注册参数，以便权限恢复后重新注册
    private var registeredKeyCode: UInt32?
    private var registeredModifiers: NSEvent.ModifierFlags?

    /// 定时检查权限恢复
    private var permissionCheckTimer: Timer?

    deinit {
        unregister()
        permissionCheckTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Registers a global hotkey with the specified key code and modifiers
    /// - Parameters:
    ///   - keyCode: The virtual key code (e.g., 9 for 'V')
    ///   - modifiers: Modifier flags (e.g., .command, .shift)
    ///   - callback: Action to execute when hotkey is triggered
    func registerHotKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        unregister()
        hotKeyCallback = callback
        registeredKeyCode = keyCode
        registeredModifiers = modifiers

        tryRegister()
    }

    /// 尝试注册 hotkey，如果权限不足则启动定时检查
    private func tryRegister() {
        let trusted = AXIsProcessTrusted()

        if trusted {
            doRegister()
            stopPermissionCheck()
        } else {
            // 请求权限
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            // 启动定时检查，等用户授权后自动注册
            startPermissionCheck()
        }
    }

    /// 实际注册全局事件监听
    private func doRegister() {
        guard let keyCode = registeredKeyCode,
              let modifiers = registeredModifiers else { return }

        let expectedModifiers = modifiers
        let expectedKeyCode = keyCode

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let eventKeyCode = event.keyCode

            if eventKeyCode == expectedKeyCode && eventModifiers == expectedModifiers {
                DispatchQueue.main.async {
                    self?.hotKeyCallback?()
                }
            }
        }

        isRegistered = true
    }

    /// Unregisters the current hotkey monitor
    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            isRegistered = false
        }
    }

    /// Returns whether a hotkey is currently registered
    func isHotKeyRegistered() -> Bool {
        return isRegistered
    }

    // MARK: - Permission Check

    /// 启动定时检查辅助功能权限
    private func startPermissionCheck() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermissionAndRegister()
        }
    }

    /// 停止定时检查
    private func stopPermissionCheck() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// 检查权限并尝试注册
    private func checkPermissionAndRegister() {
        let trusted = AXIsProcessTrusted()
        if trusted && !isRegistered {
            doRegister()
            stopPermissionCheck()
        }
    }
}
