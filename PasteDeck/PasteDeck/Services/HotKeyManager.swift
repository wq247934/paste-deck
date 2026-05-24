//
//  HotKeyManager.swift
//  PasteDeck
//
//  Manages global hotkey registration using Carbon API.
//  Carbon intercepts hotkey at system level, preventing key event from passing through to other apps.
//  Requires accessibility permission for global key event capture.
//
//  Created on 2026-05-23.
//

import Foundation
import AppKit
import Carbon

/// Manages global hotkey registration using Carbon.
/// Carbon 可以在系统底层拦截快捷键，防止按键透传到其他应用触发意外操作。
class HotKeyManager {
    // 使用单例，因为 Carbon 的事件回调是一个全局 C 函数指针
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyCallback: (() -> Void)?
    private var isRegistered = false

    /// 保存注册参数，以便权限恢复后重新注册
    private var registeredKeyCode: UInt32?
    private var registeredModifiers: NSEvent.ModifierFlags?

    /// 定时检查权限恢复
    private var permissionCheckTimer: Timer?

    private init() {
        setupEventHandler()
    }

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

    /// 实际注册全局事件监听 (使用 Carbon API)
    private func doRegister() {
        guard let keyCode = registeredKeyCode,
              let modifiers = registeredModifiers else { return }

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5044534B) // 'PDSK' - PasteDeck HotKey
        hotKeyID.id = UInt32(1)

        // 转换修饰键 (将 NSEvent 修饰键转换为 Carbon 修饰键)
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.shift)   { carbonModifiers |= UInt32(shiftKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        // 使用 Carbon 注册全局快捷键
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        isRegistered = (status == noErr)

        if !isRegistered {
            NSLog("[PasteDeck] HotKeyManager: RegisterEventHotKey failed with status \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            isRegistered = false
        }
    }

    func isHotKeyRegistered() -> Bool {
        return isRegistered
    }

    // MARK: - Private Methods

    /// 设置 Carbon 事件监听器
    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // C 语言风格的回调
        let handler: EventHandlerUPP = { (_, theEvent, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                theEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr && hotKeyID.id == 1 {
                // 触发回调
                DispatchQueue.main.async {
                    HotKeyManager.shared.hotKeyCallback?()
                }
            }
            // 返回 noErr 告诉系统：这个按键事件已被处理，请不要再传给其他 App
            return noErr
        }

        // InstallApplicationEventHandler 是宏，Swift 中使用 InstallEventHandler
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            nil
        )
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
