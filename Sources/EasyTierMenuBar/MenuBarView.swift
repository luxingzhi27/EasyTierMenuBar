import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: ServiceMonitor
    @ObservedObject var disclosureMotion: PanelDisclosureMotion
    let animatePanelExpansion: (PanelDisclosure, CGFloat) -> Void

    var body: some View {
        TopPinnedColumnLayout(spacing: 6) {
            header
            serviceCard
            nodesCard
            topologyCard

            if let message = monitor.errorMessage {
                inlineMessage(message, symbol: "exclamationmark.triangle.fill")
            }

            serviceControls
            utilityFooter
        }
        .padding(6)
        .frame(width: 392)
        .background(Color.primary.opacity(0.018))
        .onAppear {
            disclosureMotion.synchronize(
                .nodes,
                to: monitor.nodesExpanded ? nodesDetailHeight : 0
            )
            disclosureMotion.synchronize(
                .topology,
                to: monitor.topologyExpanded ? topologyDetailHeight : 0
            )
        }
        .onChange(of: nodesDetailHeight) { height in
            disclosureMotion.synchronize(.nodes, to: monitor.nodesExpanded ? height : 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(monitor.health.color)
                .frame(width: 6, height: 6)
                .shadow(color: monitor.health.color.opacity(0.45), radius: 3)

            Text("EASYTIER · LIVE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.05)
                .foregroundStyle(.secondary)

            Spacer()

            if let lastUpdated = monitor.lastUpdated {
                Text(lastUpdated, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Button {
                monitor.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(monitor.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        monitor.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: monitor.isRefreshing
                    )
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.plain)
            .help("立即刷新")
            .disabled(monitor.isRefreshing)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }

    private var serviceCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(monitor.health.color.opacity(0.13))
                    Image(systemName: monitor.health.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(monitor.health.color)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("EasyTier 服务")
                        .font(.system(size: 13, weight: .semibold))
                    Text(monitor.health.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(monitor.health.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(monitor.health.color)
                    Text(monitor.pid.map { "PID \($0)" } ?? "PID —")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)

            Rectangle()
                .fill(Color.primary.opacity(0.065))
                .frame(height: 0.5)
                .padding(.horizontal, 10)

            HStack(spacing: 0) {
                metric(title: "本机地址", value: monitor.localPeer?.ipv4 ?? "—", monospaced: true)
                metricDivider
                metric(title: "在线节点", value: "\(monitor.remotePeers.count)")
                metricDivider
                metric(title: "连接方式", value: connectionSummary)
            }
            .padding(.vertical, 8)
        }
        .panelCard(tint: monitor.health.color.opacity(0.018))
    }

    private var nodesCard: some View {
        TopPinnedColumnLayout(spacing: 0) {
            moduleHeader(
                title: "节点",
                symbol: "server.rack",
                accent: .blue,
                summary: monitor.remotePeers.isEmpty ? "暂无连接" : "\(monitor.remotePeers.count) 个在线",
                expanded: monitor.nodesExpanded
            ) {
                animatePanelExpansion(
                    .nodes,
                    monitor.nodesExpanded ? 0 : nodesDetailHeight
                )
                monitor.toggleNodesExpansion()
            }

            RevealViewportLayout(height: disclosureMotion.presentation.nodesHeight) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.065))
                        .frame(height: 0.5)
                        .padding(.horizontal, 10)

                    nodeList
                }
            }
            .opacity(disclosureMotion.presentation.nodesHeight > 0 ? 1 : 0)
            .clipped()
            .allowsHitTesting(monitor.nodesExpanded)
            .accessibilityHidden(!monitor.nodesExpanded)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .panelCard(tint: Color.blue.opacity(0.018))
    }

    private var topologyCard: some View {
        TopPinnedColumnLayout(spacing: 0) {
            moduleHeader(
                title: "连接拓扑",
                symbol: "point.3.connected.trianglepath.dotted",
                accent: .purple,
                summary: topologySummary,
                expanded: monitor.topologyExpanded
            ) {
                animatePanelExpansion(
                    .topology,
                    monitor.topologyExpanded ? 0 : topologyDetailHeight
                )
                monitor.toggleTopologyExpansion()
            }

            RevealViewportLayout(height: disclosureMotion.presentation.topologyHeight) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.065))
                        .frame(height: 0.5)
                        .padding(.horizontal, 10)

                    topologyContent
                        .frame(height: 270)
                        .padding(7)
                }
            }
            .opacity(disclosureMotion.presentation.topologyHeight > 0 ? 1 : 0)
            .clipped()
            .allowsHitTesting(monitor.topologyExpanded)
            .accessibilityHidden(!monitor.topologyExpanded)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .panelCard(tint: Color.purple.opacity(0.014))
    }

    private func moduleHeader(
        title: String,
        symbol: String,
        accent: Color,
        summary: String,
        expanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(expanded ? .degrees(90) : .zero)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nodeList: some View {
        if monitor.remotePeers.isEmpty {
            emptyState(
                symbol: "dot.radiowaves.left.and.right",
                message: monitor.health == .running ? "暂无远程节点" : "节点信息不可用"
            )
            .frame(height: 94)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(monitor.remotePeers) { peer in
                        PeerRow(peer: peer, relayDescription: monitor.relayDescription(for: peer))

                        if peer.id != monitor.remotePeers.last?.id {
                            Rectangle()
                                .fill(Color.primary.opacity(0.055))
                                .frame(height: 0.5)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: peerListHeight)
        }
    }

    @ViewBuilder
    private var topologyContent: some View {
        if monitor.topologyNodes.isEmpty {
            emptyState(symbol: "chart.dots.scatter", message: monitor.topologyError ?? "拓扑信息不可用")
        } else {
            TopologyView(monitor: monitor)
        }
    }

    private var peerListHeight: CGFloat {
        min(CGFloat(monitor.remotePeers.count) * 50, 200)
    }

    private var nodesDetailHeight: CGFloat {
        (monitor.remotePeers.isEmpty ? 94 : peerListHeight) + 0.5
    }

    private var topologyDetailHeight: CGFloat { 284.5 }

    private var serviceControls: some View {
        HStack(spacing: 6) {
            if let action = monitor.currentAction {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(action.progressTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
                .panelCard(cornerRadius: 10)
            } else {
                switch monitor.health {
                case .running, .degraded:
                    operationButton("重启服务", symbol: "arrow.clockwise", tint: .blue) { monitor.restart() }
                    operationButton("停止服务", symbol: "stop.fill", tint: .red) { monitor.stop() }
                case .stopped:
                    operationButton("启动服务", symbol: "play.fill", tint: .green) { monitor.start() }
                case .checking:
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("正在检查服务")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .panelCard(cornerRadius: 10)
                case .notInstalled:
                    Label("未找到 EasyTier 系统服务", systemImage: "questionmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .panelCard(cornerRadius: 10)
                }
            }
        }
    }

    private func operationButton(
        _ title: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelCard(tint: tint.opacity(0.025), cornerRadius: 10)
    }

    private var utilityFooter: some View {
        HStack(spacing: 8) {
            Toggle(
                "登录时启动应用",
                isOn: Binding(
                    get: { monitor.launchAtLoginEnabled },
                    set: { monitor.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)

            if monitor.launchAtLoginRequiresApproval {
                Button("需要批准") { monitor.openLoginItemsSettings() }
                    .buttonStyle(.link)
                    .font(.caption2)
            }

            Spacer()

            Button {
                monitor.quit()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .help("退出")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    private func metric(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(monospaced
                    ? .system(size: 11, weight: .medium, design: .monospaced)
                    : .system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(width: 0.5, height: 25)
    }

    private var connectionSummary: String {
        let relayedCount = monitor.remotePeers.filter {
            monitor.relayDescription(for: $0) != nil || $0.isRelay
        }.count
        guard relayedCount > 0 else { return monitor.remotePeers.isEmpty ? "—" : "全部直连" }
        return "\(relayedCount) 个中继"
    }

    private var topologySummary: String {
        guard !monitor.topologyNodes.isEmpty else { return "暂无数据" }
        return "\(monitor.topologyNodes.count) 节点 · \(monitor.topologyEdges.count) 连接"
    }

    private func emptyState(symbol: String, message: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inlineMessage(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .panelCard(tint: Color.orange.opacity(0.055), cornerRadius: 10)
    }
}

private struct PeerRow: View {
    let peer: Peer
    let relayDescription: String?

    private var accentColor: Color {
        relayDescription == nil && !peer.isRelay ? .green : .orange
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accentColor.opacity(0.12))
                Image(systemName: peer.connectionSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.hostname)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(peer.ipv4)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(peer.latMS == "-" ? "—" : "\(peer.latMS) ms")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 5) {
                    Text(connectionDetail).foregroundStyle(accentColor)
                    Text("↓\(peer.rxBytes)  ↑\(peer.txBytes)").foregroundStyle(.tertiary)
                }
                .font(.system(size: 9))
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }

    private var connectionDetail: String {
        if let relayDescription { return relayDescription }
        return peer.tunnelProto.isEmpty ? peer.connectionLabel : peer.tunnelProto
    }
}
