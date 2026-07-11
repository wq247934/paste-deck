//
//  KeyboardFocusPanel.swift
//  PasteDeck
//
//  A non-activating panel that can receive keyboard input while the app that
//  the user is working in remains active.
//

import AppKit

/// PasteDeck's shortcut-driven panels must not depend on application activation.
///
/// Starting with macOS 14, application activation is cooperative and the system
/// may reject a focus-stealing request while the user is typing, especially in
/// credential and AutoFill UI. A non-activating panel is the AppKit-supported
/// way to become key and receive keyboard events without activating PasteDeck.
final class KeyboardFocusPanel: NSPanel {
    init(
        keyboardContentRect contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer creationDeferred: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask.union(.nonactivatingPanel),
            backing: backing,
            defer: creationDeferred
        )

        // The entire panel is keyboard-oriented, so it must become key even
        // when the initial click or focus target is not a text field.
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        hidesOnDeactivate = false
    }

    @available(*, unavailable, message: "KeyboardFocusPanel must be created programmatically")
    required init?(coder: NSCoder) {
        fatalError("KeyboardFocusPanel must be created programmatically")
    }

    override var canBecomeKey: Bool { true }

    // The user's current app remains the main application; PasteDeck only
    // borrows key-window status for direct clipboard keyboard interaction.
    override var canBecomeMain: Bool { false }
}
