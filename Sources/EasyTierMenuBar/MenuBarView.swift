import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: ServiceMonitor

    var body: some View {
        VStack(spacing: 0) {
            header
            overview
            contentSection

            if let message = monitor.errorMessage {
                inlineMessage(message, symbol: "exclamationmark.triangle.fill")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            footer
        }
        .frame(width: 392)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .modifier(PanelSurfaceModifier())
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)

                Circle()
                    .fill(monitor.health.color)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle().stroke(.black.opacity(0.35), lineWidth: 1.5)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("EasyTier")
                        .font(.system(size: 15, weight: .semibold))

                    Text(monitor.health.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(monitor.health.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(monitor.health.color.opacity(0.11), in: Capsule())
                }

                Text(monitor.health.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button {
                monitor.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(monitor.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        monitor.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: monitor.isRefreshing
                    )
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.055), in: Circle())
            .overlay {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .help("立即刷新")
            .disabled(monitor.isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 12)
    }

    private var overview: some View {
        HStack(spacing: 0) {
            overviewItem(title: "PID", value: monitor.pid.map(String.init) ?? "—")
            overviewDivider
            overviewItem(title: "本机地址", value: monitor.localPeer?.ipv4 ?? "—", monospaced: true)
            overviewDivider
            overviewItem(title: "在线节点", value: "\(monitor.remotePeers.count)")
        }
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
    }

    private func overviewItem(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(monospaced ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 0.5, height: 27)
    }

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("视图", selection: $monitor.selectedSection) {
                    ForEach(PanelSection.allCases) { section in
                        Label(section.title, systemImage: section.symbolName).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 174)

                Spacer()

                if let lastUpdated = monitor.lastUpdated {
                    Label {
                        Text(lastUpdated, style: .time)
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }
            }

            switch monitor.selectedSection {
            case .nodes:
                nodeList
            case .topology:
                topologyContent
                    .frame(height: 258)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var nodeList: some View {
        if monitor.remotePeers.isEmpty {
            emptyState(
                symbol: "point.3.filled.connected.trianglepath.dotted",
                message: monitor.health == .running ? "暂无远程节点" : "节点信息不可用"
            )
            .frame(height: 104)
            .modifier(ListContainerModifier())
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(monitor.remotePeers) { peer in
                        PeerRow(
                            peer: peer,
                            relayDescription: monitor.relayDescription(for: peer)
                        )

                        if peer.id != monitor.remotePeers.last?.id {
                            Rectangle()
                                .fill(Color.primary.opacity(0.065))
                                .frame(height: 0.5)
                                .padding(.leading, 42)
                        }
                    }
                }
            }
            .frame(height: peerListHeight)
            .modifier(ListContainerModifier())
        }
    }

    @ViewBuilder
    private var topologyContent: some View {
        if monitor.topologyNodes.isEmpty {
            emptyState(
                symbol: "chart.dots.scatter",
                message: monitor.topologyError ?? "拓扑信息不可用"
            )
            .modifier(ListContainerModifier())
        } else {
            TopologyView(monitor: monitor)
        }
    }

    private var peerListHeight: CGFloat {
        let rowHeight: CGFloat = 52
        return min(CGFloat(monitor.remotePeers.count) * rowHeight, 240)
    }

    private func emptyState(symbol: String, message: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 0.5)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(monitor.health.color)
                            .frame(width: 7, height: 7)
                        Text("系统服务")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    serviceControls
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)

                HStack(spacing: 8) {
                    Toggle(
                        "登录时启动",
                        isOn: Binding(
                            get: { monitor.launchAtLoginEnabled },
                            set: { monitor.setLaunchAtLogin($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)

                    if monitor.launchAtLoginRequiresApproval {
                        Button("需要批准") {
                            monitor.openLoginItemsSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }

                    Spacer()

                    Button("退出") {
                        monitor.quit()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let error = monitor.launchAtLoginError {
                    inlineMessage(error, symbol: "exclamationmark.circle")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.018))
        }
    }

    @ViewBuilder
    private var serviceControls: some View {
        if let action = monitor.currentAction {
            ProgressView()
                .controlSize(.small)
            Text(action.progressTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch monitor.health {
            case .stopped:
                Button {
                    monitor.start()
                } label: {
                    Label("启动", systemImage: "play.fill")
                }
                .controlSize(.small)
                .modifier(GlassButtonModifier(prominent: true))

            case .running, .degraded:
                Button {
                    monitor.restart()
                } label: {
                    Label("重启", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .modifier(GlassButtonModifier())

                Button(role: .destructive) {
                    monitor.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .controlSize(.small)
                .modifier(GlassButtonModifier())

            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("正在检查")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .notInstalled:
                Text("服务未安装")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inlineMessage(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private extension PanelSection {
    var symbolName: String {
        switch self {
        case .nodes: return "list.bullet"
        case .topology: return "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct PanelSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct ListContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(0.024), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.065), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct GlassButtonModifier: ViewModifier {
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct PeerRow: View {
    let peer: Peer
    let relayDescription: String?

    private var accentColor: Color { peer.isRelay ? .orange : .green }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: peer.connectionSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.hostname)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(peer.ipv4)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(peer.latMS == "-" ? "—" : "\(peer.latMS) ms")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 5) {
                    Text(connectionDetail)
                        .foregroundStyle(accentColor)
                    Text("↓\(peer.rxBytes)  ↑\(peer.txBytes)")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 9))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    private var connectionDetail: String {
        if let relayDescription { return relayDescription }
        return peer.tunnelProto.isEmpty ? peer.connectionLabel : peer.tunnelProto
    }
}
