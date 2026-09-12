import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let monitor = ServiceMonitor()
    private let panelCornerRadius: CGFloat = 20

    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var panelHost: PanelGlassHost!
    private var hostingView: NSHostingView<AnyView>!
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var lastContentSize = CGSize(width: 392, height: 360)
    private var dismissGeneration = 0
    private let disclosureMotion = PanelDisclosureMotion()
    private lazy var heightAnimator: any PanelHeightAnimating = {
        let apply: (CGFloat) -> Void = { [weak self] height in
            self?.applyAnimatedPanelHeight(height)
        }
        if #available(macOS 14.0, *) {
            return DisplayLinkPanelHeightAnimator(
                apply: apply,
                screen: { [weak self] in self?.panel.screen }
            )
        }
        return TimerPanelHeightAnimator(apply: apply)
    }()

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
        installEventMonitors()
        monitor.refreshOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitors()
        monitor.panelDidDisappear()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.setAccessibilityTitle("EasyTier 状态")
        button.toolTip = "EasyTier"
        updateStatusItem(for: monitor.health)
    }

    private func configurePanel() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: lastContentSize),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        panelHost = PanelGlassHost(cornerRadius: panelCornerRadius)
        panel.contentView = panelHost

        let content = MenuBarView(
            monitor: monitor,
            disclosureMotion: disclosureMotion,
            animatePanelExpansion: { [weak self] section, targetHeight in
                self?.animatePanelExpansion(section, targetHeight: targetHeight)
            }
        )
            .modifier(PanelContentSizeReader { [weak self] size in
                self?.contentSizeDidChange(size)
            })
        hostingView = TopPinnedHostingView(rootView: AnyView(content))
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = panelCornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panelHost.setContentView(hostingView)

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        if fittingSize.width > 1, fittingSize.height > 1 {
            lastContentSize = fittingSize
            panel.setContentSize(fittingSize)
        }
    }

    private func observeMonitor() {
        monitor.$health
            .receive(on: RunLoop.main)
            .sink { [weak self] health in
                self?.updateStatusItem(for: health)
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

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53, panel.isVisible {
                dismissPanel()
                return nil
            }

            guard let button = statusItem.button, event.window == button.window else {
                return event
            }
            if event.modifierFlags.contains(.command) { return event }

            switch event.type {
            case .leftMouseDown:
                togglePanel()
            case .rightMouseDown:
                dismissPanel()
                showContextMenu(event, for: button)
            default:
                return event
            }
            return nil
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPanel()
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func togglePanel() {
        panel.isVisible ? dismissPanel() : showPanel()
    }

    private func showPanel() {
        dismissGeneration &+= 1
        heightAnimator.cancel()
        disclosureMotion.finish()
        hostingView.layoutSubtreeIfNeeded()
        setPanelFrame(size: lastContentSize)
        monitor.panelDidAppear()
        statusItem.button?.highlight(true)
        DistributedNotificationCenter.default().post(name: .beginMenuTracking, object: nil)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func dismissPanel() {
        guard panel?.isVisible == true else { return }
        heightAnimator.cancel()
        disclosureMotion.finish()
        dismissGeneration &+= 1
        let generation = dismissGeneration
        monitor.panelDidDisappear()
        statusItem.button?.highlight(false)
        DistributedNotificationCenter.default().post(name: .endMenuTracking, object: nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.dismissGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    private func contentSizeDidChange(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        lastContentSize = size
        guard panel.isVisible else {
            panel.setContentSize(size)
            return
        }

        // Disclosure animation owns the window target. Geometry updates during
        // that interval are presentation samples, not new destinations.
        guard !disclosureMotion.isAnimating,
              !monitor.isExpansionAnimating,
              !heightAnimator.isAnimating else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, panel.isVisible else { return }
            guard !disclosureMotion.isAnimating,
                  !monitor.isExpansionAnimating,
                  !heightAnimator.isAnimating else { return }
            setPanelFrame(size: size)
        }
    }

    private func animatePanelExpansion(
        _ section: PanelDisclosure,
        targetHeight: CGFloat
    ) {
        guard panel.isVisible else { return }
        let currentRevealHeight = disclosureMotion.height(for: section)
        let panelStartHeight = panel.frame.height
        let panelTargetHeight = max(1, panelStartHeight + targetHeight - currentRevealHeight)

        disclosureMotion.begin(
            section,
            targetHeight: targetHeight,
            windowStart: panelStartHeight,
            windowTarget: panelTargetHeight
        )

        heightAnimator.retarget(
            to: panelTargetHeight,
            from: panelStartHeight,
            onSettle: { [weak self] in
                self?.completePanelExpansion()
            }
        )
    }

    private func applyAnimatedPanelHeight(_ height: CGFloat) {
        guard panel.isVisible else { return }
        disclosureMotion.apply(windowHeight: height)
        setPanelFrame(
            size: CGSize(width: lastContentSize.width, height: max(1, height)),
            display: false
        )
    }

    private func completePanelExpansion() {
        disclosureMotion.finish()
        DispatchQueue.main.async { [weak self] in
            guard let self, panel.isVisible else { return }
            hostingView.layoutSubtreeIfNeeded()
            reconcilePanelSize()
        }
    }

    private func reconcilePanelSize() {
        guard panel.isVisible else { return }
        setPanelFrame(size: lastContentSize)
    }

    private func setPanelFrame(size: CGSize, display: Bool = true) {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = screen.visibleFrame
        var panelSize = size
        panelSize.height = min(panelSize.height, buttonRect.minY - visibleFrame.minY - 10)

        let preferredX = buttonRect.minX - 2
        let x = min(
            max(preferredX, visibleFrame.minX + 2),
            visibleFrame.maxX - panelSize.width - 2
        )
        let y = buttonRect.minY - panelSize.height - 2
        let targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
        guard panel.frame != targetFrame else { return }
        panel.setFrame(targetFrame, display: display)
    }

    private func showContextMenu(_ event: NSEvent, for button: NSStatusBarButton) {
        let menu = NSMenu(title: "EasyTier")

        let refreshItem = NSMenuItem(title: "刷新状态", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 EasyTier 状态", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func refreshFromMenu() {
        monitor.refreshNow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.dismissPanel()
        }
    }
}

private struct PanelContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

private struct PanelContentSizeReader: ViewModifier {
    let onChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            .edgesIgnoringSafeArea(.all)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: PanelContentSizePreferenceKey.self, value: geometry.size)
                }
            }
            .onPreferenceChange(PanelContentSizePreferenceKey.self, perform: onChange)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private final class TopPinnedHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    override var safeAreaRect: NSRect { bounds }
}

private extension Notification.Name {
    static let beginMenuTracking = Notification.Name("com.apple.HIToolbox.beginMenuTrackingNotification")
    static let endMenuTracking = Notification.Name("com.apple.HIToolbox.endMenuTrackingNotification")
}
