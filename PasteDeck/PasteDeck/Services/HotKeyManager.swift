//
//  HotKeyManager.swift
//  PasteDeck
//
//  Registers multiple independent global hotkeys with Carbon.
//

import AppKit
import Carbon
import Foundation

/// PasteDeck 可独立注册的全局快捷键；raw value 直接作为 Carbon hotkey id，已有值不可复用。
enum HotKeyIdentifier: UInt32, CaseIterable {
    /// 打开或关闭剪贴板主面板。
    case mainPanel = 1
    /// 翻译当前前台应用中的选中文本。
    case selectionTranslation = 2
    /// 启动区域截图、OCR 并翻译。
    case screenshotTranslation = 3
    /// 打开可输入原文的翻译窗口。
    case inputTranslation = 4
}

/// 使用 Carbon 注册多组全局快捷键；快捷键注册本身不依赖辅助功能权限。
final class HotKeyManager {
    static let shared = HotKeyManager()

    private struct Registration {
        /// Carbon 返回的注册引用；nil 表示配置已保存但尚未成功注册。
        var reference: EventHotKeyRef?
        /// macOS 虚拟键码，例如 V 为 9、D 为 2。
        let keyCode: UInt32
        /// AppKit 修饰键集合，注册前转换为 Carbon flags。
        let modifiers: NSEvent.ModifierFlags
        /// 系统触发该快捷键后在主线程执行的业务动作。
        let callback: () -> Void
    }

    private var registrations: [HotKeyIdentifier: Registration] = [:]
    private init() {
        setupEventHandler()
    }

    deinit {
        unregister()
    }

    /// 兼容旧调用方：注册主面板快捷键，不影响已经注册的翻译快捷键。
    func registerHotKey(
        keyCode: UInt32,
        modifiers: NSEvent.ModifierFlags,
        callback: @escaping () -> Void
    ) {
        register(identifier: .mainPanel, keyCode: keyCode, modifiers: modifiers, callback: callback)
    }

    /// 注册或替换指定业务快捷键；每个业务标识只保留一组 Carbon 注册。
    func register(
        identifier: HotKeyIdentifier,
        keyCode: UInt32,
        modifiers: NSEvent.ModifierFlags,
        callback: @escaping () -> Void
    ) {
        unregister(identifier: identifier)
        registrations[identifier] = Registration(
            reference: nil,
            keyCode: keyCode,
            modifiers: modifiers,
            callback: callback
        )
        registerWithCarbon(identifier: identifier)
    }

    /// 仅注销指定业务快捷键，其他快捷键继续工作。
    func unregister(identifier: HotKeyIdentifier) {
        if let reference = registrations[identifier]?.reference {
            UnregisterEventHotKey(reference)
        }
        registrations.removeValue(forKey: identifier)
    }

    /// 注销 PasteDeck 当前持有的全部全局快捷键。
    func unregister() {
        for registration in registrations.values {
            if let reference = registration.reference {
                UnregisterEventHotKey(reference)
            }
        }
        registrations.removeAll()
    }

    func isHotKeyRegistered(identifier: HotKeyIdentifier = .mainPanel) -> Bool {
        registrations[identifier]?.reference != nil
    }

    /// Carbon 全局快捷键不依赖辅助功能权限；辅助功能仅用于读取选区和模拟按键。
    private func registerWithCarbon(identifier: HotKeyIdentifier) {
        guard var registration = registrations[identifier], registration.reference == nil else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5044534B), id: identifier.rawValue)
        var carbonModifiers: UInt32 = 0
        if registration.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if registration.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if registration.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if registration.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            registration.keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr else { return }
        registration.reference = reference
        registrations[identifier] = registration
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  let identifier = HotKeyIdentifier(rawValue: hotKeyID.id),
                  let callback = HotKeyManager.shared.registrations[identifier]?.callback else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async(execute: callback)
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            nil
        )
    }

}
