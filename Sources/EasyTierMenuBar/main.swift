import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = ServiceMonitor()
    private var statusItem: NSStatusItem!
    private var panel: GlassPanel!
    private var hostingController: NSHostingController<MenuBarView>!
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePanel()
        observeMonitor()
        monitor.refreshOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventMonitoring()
        monitor.panelDidDisappear()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem(for: monitor.health)
    }

    private func configurePanel() {
        hostingController = NSHostingController(rootView: MenuBarView(monitor: monitor))

        panel = GlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        resizePanel(keepingTopEdge: false)
    }

    private func observeMonitor() {
        monitor.$health
            .receive(on: RunLoop.main)
            .sink { [weak self] health in
                self?.updateStatusItem(for: health)
            }
            .store(in: &cancellables)

        monitor.$panelLayoutRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resizePanel(keepingTopEdge: true)
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(for health: ServiceHealth) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: health.symbolName, accessibilityDescription: health.title)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "EasyTier：\(health.title)"
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        monitor.panelDidAppear()
        resizePanel(keepingTopEdge: false)
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        startEventMonitoring()
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        monitor.panelDidDisappear()
        stopEventMonitoring()
    }

    private func resizePanel(keepingTopEdge: Bool) {
        guard panel != nil, hostingController != nil else { return }
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        let oldFrame = panel.frame
        var newFrame = oldFrame
        newFrame.size = fittingSize
        if keepingTopEdge && panel.isVisible {
            newFrame.origin.y = oldFrame.maxY - fittingSize.height
        }
        panel.setFrame(newFrame, display: true, animate: false)
    }

    private func positionPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let preferredX = buttonRect.midX - panelSize.width / 2
        let x = min(max(preferredX, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        let y = buttonRect.minY - panelSize.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func startEventMonitoring() {
        stopEventMonitoring()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                closePanel()
                return nil
            }
            if event.type != .keyDown,
               event.window !== panel,
               event.window !== statusItem.button?.window {
                closePanel()
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func stopEventMonitoring() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}

private final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
