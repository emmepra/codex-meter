import AppKit
import SwiftUI

private final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class PanelHostingView: NSHostingView<AnyView> {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// A real window positioned in screen coordinates, independent of NSPopover placement.
@MainActor
final class StatusPanel {
    private let window: PanelWindow
    private let hosting: PanelHostingView
    private let anchor: () -> NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var positionScheduled = false
    private var outsideClickMonitor: Any?
    private var anchorTimer: Timer?
    private var positionedAnchor: NSRect?

    var isVisible: Bool { window.isVisible }
    var frame: NSRect { window.frame }

    init(content: AnyView, anchor: @escaping () -> NSWindow?) {
        self.anchor = anchor
        window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 270, height: 100),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        hosting = PanelHostingView(rootView: AnyView(content.fixedSize(horizontal: false, vertical: true)))
        hosting.sizingOptions = [.intrinsicContentSize]
        window.title = "Codex Meter"
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: window.contentView!.bounds)
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        window.contentView = background
        window.onCancel = { [weak self] in self?.hide() }
        hosting.onLayout = { [weak self] in self?.schedulePosition() }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let changed = event.object as? NSWindow, changed === self.anchor() else { return }
                    self.schedulePosition()
                }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePosition() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        anchorTimer?.invalidate()
    }

    @discardableResult
    func show() -> Bool {
        guard position() else { return false }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if window.isVisible {
            if outsideClickMonitor == nil {
                // Other apps' clicks include other menu bar items. Events in our
                // own SwiftUI menu remain untouched.
                outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.hide() }
                }
            }
            if anchorTimer == nil {
                // System-hosted status items may move without a local window
                // notification. Watch only while open, and lay out only on change.
                anchorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        guard let anchor = self.anchor(), anchor.isVisible, anchor.screen != nil else {
                            self.hide()
                            return
                        }
                        if anchor.frame != self.positionedAnchor { self.schedulePosition() }
                    }
                }
            }
        }
        return window.isVisible
    }

    func hide() {
        window.orderOut(nil)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        anchorTimer?.invalidate()
        anchorTimer = nil
    }

    /// Re-evaluate after SwiftUI layout or a menu bar item/screen change.
    func schedulePosition() {
        guard window.isVisible, !positionScheduled else { return }
        positionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.positionScheduled = false
            if self.window.isVisible, !self.position() { self.hide() }
        }
    }

    @discardableResult
    private func position() -> Bool {
        guard let anchor = anchor(), anchor.isVisible, anchor.frame.height > 0,
              let screen = anchor.screen else { return false }
        hosting.layoutSubtreeIfNeeded()
        let measured = hosting.fittingSize
        // AppKit rounds window frames to whole points. Match that rounding so
        // fractional SwiftUI sizes cannot trigger repeated resize requests.
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        var target = PanelPlacement.frame(anchor: anchor.frame, size: size, screen: screen.frame)
        target.origin.x = target.origin.x.rounded()
        target.origin.y = target.origin.y.rounded()
        guard target.width > 0, target.height > 0 else { return false }
        // Set origin and size together: content growth must never move the top edge.
        if window.frame != target { window.setFrame(target, display: true, animate: false) }
        positionedAnchor = anchor.frame
        return true
    }
}
