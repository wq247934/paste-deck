//
//  HotKeyManager.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import Foundation
import Carbon
import AppKit

class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyCallback: (() -> Void)?
    private var hotKeyID: UInt32 = 1

    init() {}

    deinit {
        unregister()
    }

    func registerHotKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, callback: @escaping () -> Void) {
        unregister()
        hotKeyCallback = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                HotKeyManager.hotKeyHandler(nextHandler: nil, event: event, userData: userData)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        var hotKeyID = EventHotKeyID(signature: OSType(0x5044_4B49), id: self.hotKeyID)

        RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private static func hotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
        guard let userData = userData else { return OSStatus(eventNotHandledErr) }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.hotKeyCallback?()
        return noErr
    }
}
