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

    deinit {
        unregister()
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

        // Check accessibility permission - required for global event monitoring
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Request permission via system dialog
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            return
        }

        // Register global keyDown event monitor
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
}
