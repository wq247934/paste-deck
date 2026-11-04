import AgentSpeedCore
import AgentSpeedOrbModel
import AppKit
import SwiftUI

/// One entry of a source chip: a colour dot and a name, or a status in the secondary color.
struct OrbChipItem: Equatable, Identifiable {
    var id: String
    var color: RGBColor?
    var text: String
    var secondary: Bool
}

/// The source chip (DESIGN 2b, Identity at a glance): a capsule 18 pt tall with 6 pt colour dots and 11 pt semibold
/// names, on a smoked (dark) or frosted (light) fill with a hairline border and a soft shadow.
struct OrbChipView: View {
    let items: [OrbChipItem]
    var trailing: (label: String, action: () -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    if let color = item.color {
                        Circle()
                            .fill((dark ? color : color.darkened(0.12)).color)
                            .opacity(item.secondary ? 0.45 : 1)
                            .frame(width: 6, height: 6)
                    }
                    Text(item.text)
                        .foregroundStyle(item.secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
            }
            if let trailing {
                Text("·").foregroundStyle(.secondary)
                Button(trailing.label, action: trailing.action)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(
            Capsule(style: .continuous)
                .fill(dark ? Color(.sRGB, red: 20 / 255, green: 22 / 255, blue: 30 / 255, opacity: 0.82)
                    : Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.9))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(dark ? 0.35 : 0.14), radius: 4, y: 1.5)
        .padding(8)
        .accessibilityElement(children: .combine)
    }
}

/// A hosting view that takes the first click, so the undo chip's button works without activating the app.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A non-activating overlay panel that may extend past the orb window (chips, undo chip).
@MainActor
final class OrbChipPanel {
    let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private(set) var isShown = false
    private var generation = 0

    init(interactive: Bool) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = !interactive
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.alphaValue = 0
        hosting = interactive ? FirstMouseHostingView(rootView: AnyView(EmptyView())) : NSHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = hosting
    }

    /// Shows `view` with its natural size placed by `frame(size)` (screen coordinates).
    func show<V: View>(_ view: V, level: NSWindow.Level, appearance: NSAppearance?, place: (CGSize) -> CGRect) {
        hosting.rootView = AnyView(view)
        hosting.appearance = appearance
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setFrame(place(size), display: true)
        panel.level = level
        generation &+= 1
        if !isShown {
            isShown = true
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    /// Moves the panel without changing its content (the orb moved).
    func reposition(place: (CGSize) -> CGRect) {
        guard isShown else { return }
        panel.setFrameOrigin(place(panel.frame.size).origin)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        generation &+= 1
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Guides shown while dragging an orb (DESIGN 2b, Alignment): 1 pt dashed lines in the accent color at 60 %, in a
/// click-through overlay over the display.
@MainActor
final class OrbGuidesWindow {
    private let window: NSWindow
    private let shape = CAShapeLayer()
    private var shown = false

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(shape)
        window.contentView = view
        shape.fillColor = nil
        shape.lineWidth = 1
        shape.lineDashPattern = [4, 3]
        shape.actions = ["path": NSNull(), "strokeColor": NSNull()]
    }

    func show(_ guides: [OrbGuide], on screen: NSScreen?) {
        guard let screen, !guides.isEmpty else {
            hide()
            return
        }
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        shape.frame = CGRect(origin: .zero, size: screen.frame.size)
        shape.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        let path = CGMutablePath()
        let origin = screen.frame.origin
        for guide in guides {
            switch guide.axis {
            case .vertical:
                path.move(to: CGPoint(x: guide.position - origin.x + 0.5, y: guide.from - origin.y))
                path.addLine(to: CGPoint(x: guide.position - origin.x + 0.5, y: guide.to - origin.y))
            case .horizontal:
                path.move(to: CGPoint(x: guide.from - origin.x, y: guide.position - origin.y + 0.5))
                path.addLine(to: CGPoint(x: guide.to - origin.x, y: guide.position - origin.y + 0.5))
            }
        }
        shape.path = path
        if !shown {
            shown = true
            window.orderFrontRegardless()
        }
    }

    func hide() {
        guard shown else { return }
        shown = false
        shape.path = nil
        window.orderOut(nil)
    }
}
