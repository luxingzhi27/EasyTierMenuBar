import AppKit
import QuartzCore
import SwiftUI

/// The panel has one native window backdrop. Cards use a within-window
/// material so resizing does not repeatedly resample the desktop.
final class PanelGlassHost: NSView {
    private let backdrop: NSView

    init(cornerRadius: CGFloat) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            backdrop = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            backdrop = material
        }

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setContentView(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content, positioned: .above, relativeTo: backdrop)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

struct PanelRowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct PanelCardModifier: ViewModifier {
    var tint: Color = .clear
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    PanelRowMaterial()
                    tint
                }
                .clipShape(shape)
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
    }
}

extension View {
    func panelCard(tint: Color = .clear, cornerRadius: CGFloat = 14) -> some View {
        modifier(PanelCardModifier(tint: tint, cornerRadius: cornerRadius))
    }
}

enum PanelDisclosure {
    case nodes
    case topology
}

struct PanelDisclosurePresentation: Equatable {
    var nodesHeight: CGFloat = 94.5
    var topologyHeight: CGFloat = 0
}

/// A single presentation sample drives both the disclosure viewport and the
/// NSPanel frame. No independent SwiftUI height animation is involved.
@MainActor
final class PanelDisclosureMotion: ObservableObject {
    @Published private(set) var presentation = PanelDisclosurePresentation()

    private var activeSection: PanelDisclosure?
    private var revealStart: CGFloat = 0
    private var revealTarget: CGFloat = 0
    private var windowStart: CGFloat = 0
    private var windowTarget: CGFloat = 0

    var isAnimating: Bool { activeSection != nil }

    func height(for section: PanelDisclosure) -> CGFloat {
        switch section {
        case .nodes: return presentation.nodesHeight
        case .topology: return presentation.topologyHeight
        }
    }

    func synchronize(_ section: PanelDisclosure, to height: CGFloat) {
        guard !isAnimating else { return }
        setHeight(height, for: section)
    }

    func begin(
        _ section: PanelDisclosure,
        targetHeight: CGFloat,
        windowStart: CGFloat,
        windowTarget: CGFloat
    ) {
        activeSection = section
        revealStart = height(for: section)
        revealTarget = targetHeight
        self.windowStart = windowStart
        self.windowTarget = windowTarget
    }

    func apply(windowHeight: CGFloat) {
        guard let activeSection else { return }
        let distance = windowTarget - windowStart
        let phase = abs(distance) < 0.001
            ? CGFloat(1)
            : min(1, max(0, (windowHeight - windowStart) / distance))
        setHeight(revealStart + (revealTarget - revealStart) * phase, for: activeSection)
    }

    func finish() {
        guard let activeSection else { return }
        setHeight(revealTarget, for: activeSection)
        self.activeSection = nil
    }

    private func setHeight(_ height: CGFloat, for section: PanelDisclosure) {
        var next = presentation
        switch section {
        case .nodes: next.nodesHeight = max(0, height)
        case .topology: next.topologyHeight = max(0, height)
        }
        guard next != presentation else { return }
        presentation = next
    }
}

/// Explicit top-leading placement keeps every sibling's coordinate independent
/// of the host view's changing height.
struct TopPinnedColumnLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? subviews.map {
            $0.sizeThatFits(.unspecified).width
        }.max() ?? 0
        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
        return CGSize(
            width: width,
            height: sizes.map(\.height).reduce(0, +)
                + CGFloat(max(0, sizes.count - 1)) * spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            y += size.height + spacing
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? { nil }
}

/// Reports exactly the sampled reveal height while always placing its natural
/// content at the viewport's top edge.
struct RevealViewportLayout: Layout {
    let height: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: max(0, height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}

@MainActor
protocol PanelHeightAnimating: AnyObject {
    var isAnimating: Bool { get }
    var target: CGFloat { get }
    func retarget(to target: CGFloat, from current: CGFloat, onSettle: (() -> Void)?)
    func cancel()
}

/// Drives the panel frame from the display clock using the same damped spring
/// as the SwiftUI disclosure content. Keeping both tracks mathematically in
/// phase prevents the window edge from overtaking the revealed content.
@available(macOS 14.0, *)
@MainActor
final class DisplayLinkPanelHeightAnimator: NSObject, PanelHeightAnimating {
    private let apply: (CGFloat) -> Void
    private let screen: () -> NSScreen?
    private var displayLink: CADisplayLink?
    private var startPosition: CGFloat = 0
    private var startVelocity: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?

    private let response = 0.32
    private lazy var omega = 2 * Double.pi / response

    private(set) var isAnimating = false
    private(set) var target: CGFloat = 0

    init(apply: @escaping (CGFloat) -> Void, screen: @escaping () -> NSScreen?) {
        self.apply = apply
        self.screen = screen
    }

    deinit {
        displayLink?.invalidate()
    }

    func retarget(to target: CGFloat, from current: CGFloat, onSettle: (() -> Void)?) {
        let now = CACurrentMediaTime()
        if isAnimating {
            let elapsed = now - startTime
            startPosition = position(at: elapsed)
            startVelocity = velocity(at: elapsed)
        } else {
            startPosition = current
            startVelocity = 0
        }

        self.target = target
        startTime = now
        completion = onSettle

        guard abs(startPosition - target) > 0.5 else {
            finish()
            return
        }

        isAnimating = true
        if displayLink == nil, let screen = screen() ?? NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func cancel() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        completion = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = link.targetTimestamp - startTime
        guard elapsed > 0 else { return }
        let position = position(at: elapsed)
        let velocity = velocity(at: elapsed)

        if (abs(position - target) < 0.25 && abs(velocity) < 2) || elapsed > 2 {
            finish()
        } else {
            apply(position)
        }
    }

    private func finish() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        apply(target)
        let action = completion
        completion = nil
        action?()
    }

    private func position(at elapsed: CFTimeInterval) -> CGFloat {
        let displacement = startPosition - target
        let linearCoefficient = startVelocity + omega * displacement
        return target + exp(-omega * elapsed)
            * (displacement + linearCoefficient * elapsed)
    }

    private func velocity(at elapsed: CFTimeInterval) -> CGFloat {
        let displacement = startPosition - target
        let linearCoefficient = startVelocity + omega * displacement
        let wave = displacement + linearCoefficient * elapsed
        return exp(-omega * elapsed) * (linearCoefficient - omega * wave)
    }
}

/// macOS 13 fallback for systems without `NSScreen.displayLink`.
@MainActor
final class TimerPanelHeightAnimator: PanelHeightAnimating {
    private let apply: (CGFloat) -> Void
    private var timer: Timer?
    private var start: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    private var completion: (() -> Void)?

    private(set) var isAnimating = false
    private(set) var target: CGFloat = 0

    init(apply: @escaping (CGFloat) -> Void) {
        self.apply = apply
    }

    func retarget(to target: CGFloat, from current: CGFloat, onSettle: (() -> Void)?) {
        cancel()
        self.target = target
        start = current
        startTime = CACurrentMediaTime()
        completion = onSettle
        isAnimating = true

        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        isAnimating = false
        timer?.invalidate()
        timer = nil
        completion = nil
    }

    private func step() {
        let progress = min(1, (CACurrentMediaTime() - startTime) / 0.32)
        let eased = 1 - pow(1 - progress, 3)
        apply(start + (target - start) * eased)
        guard progress >= 1 else { return }

        isAnimating = false
        timer?.invalidate()
        timer = nil
        let action = completion
        completion = nil
        action?()
    }
}
