import SwiftUI

struct TopologyView: View {
    @ObservedObject var monitor: ServiceMonitor

    private var nodes: [TopologyNode] { monitor.topologyNodes }
    private var edges: [TopologyEdge] { monitor.topologyEdges }
    private var localNodeID: String? { monitor.localTopologyNodeID }
    private var relayedNodeIDs: Set<String> { monitor.relayedNodeIDs }
    private var relayEdgeIDs: Set<String> { monitor.relayEdgeIDs }

    var body: some View {
        VStack(spacing: 6) {
            legend
            GeometryReader { proxy in
                let positions = layeredNodePositions(in: proxy.size)

                ZStack {
                    graphBackground

                    Canvas { context, _ in
                        drawEdges(context: &context, positions: positions)
                    }

                    ForEach(nodes) { node in
                        CompactTopologyNode(
                            node: node,
                            isLocal: node.nodeID == localNodeID,
                            isRelayed: relayedNodeIDs.contains(node.nodeID),
                            isHovered: monitor.hoveredTopologyNodeID == node.nodeID
                        )
                        .position(positions[node.nodeID] ?? .zero)
                        .zIndex(2)
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let hitNodeID = hitTestNode(
                                    at: location,
                                    positions: positions
                                )
                                if monitor.hoveredTopologyNodeID != hitNodeID {
                                    monitor.hoveredTopologyNodeID = hitNodeID
                                }
                            case .ended:
                                if monitor.hoveredTopologyNodeID != nil {
                                    monitor.hoveredTopologyNodeID = nil
                                }
                            }
                        }
                        .zIndex(5)

                    if let hoveredNode = hoveredNode,
                       let nodePosition = positions[hoveredNode.nodeID] {
                        TopologyNodeDetail(
                            node: hoveredNode,
                            route: route(for: hoveredNode),
                            isLocal: hoveredNode.nodeID == localNodeID
                        )
                        .position(detailPosition(for: nodePosition, in: proxy.size))
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(10)
                    }
                }
                .animation(.easeOut(duration: 0.14), value: monitor.hoveredTopologyNodeID)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 0.5)
        }
    }

    private var hoveredNode: TopologyNode? {
        guard let hoveredID = monitor.hoveredTopologyNodeID else { return nil }
        return nodes.first { $0.nodeID == hoveredID }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendItem(color: .green, title: "本机")
            LegendItem(color: .blue, title: "直连")
            LegendItem(color: .orange, title: "中继路径")
            Spacer()
            Text("悬浮查看详情")
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
    }

    private var graphBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.012))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
            }
    }

    /// Places nodes in hop-count columns: local, direct, then relayed hops.
    private func layeredNodePositions(in size: CGSize) -> [String: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let local = nodes.first(where: { $0.nodeID == localNodeID }) ?? nodes[0]
        let levels = hopLevels(from: local.nodeID)
        let maximumLevel = max(1, levels.values.max() ?? 1)
        let horizontalInset: CGFloat = 48
        let verticalInset: CGFloat = 24
        var groups: [Int: [TopologyNode]] = [:]

        for node in nodes {
            let level = min(levels[node.nodeID] ?? maximumLevel + 1, maximumLevel + 1)
            groups[level, default: []].append(node)
        }

        let actualMaximumLevel = max(1, groups.keys.max() ?? 1)
        var positions: [String: CGPoint] = [:]
        for (level, levelNodes) in groups {
            let sortedNodes = levelNodes.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            let x = horizontalInset +
                CGFloat(level) / CGFloat(actualMaximumLevel) * (size.width - horizontalInset * 2)
            let availableHeight = max(1, size.height - verticalInset * 2)

            for (index, node) in sortedNodes.enumerated() {
                let y: CGFloat
                if sortedNodes.count == 1 {
                    y = size.height / 2
                } else {
                    y = verticalInset + CGFloat(index) / CGFloat(sortedNodes.count - 1) * availableHeight
                }
                positions[node.nodeID] = CGPoint(x: x, y: y)
            }
        }
        return positions
    }

    private func hopLevels(from localID: String) -> [String: Int] {
        var result = [localID: 0]
        var queue = [localID]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard let level = result[current],
                  let node = nodes.first(where: { $0.nodeID == current }) else { continue }

            for neighbor in node.directPeers.map(\.nodeID) where result[neighbor] == nil {
                result[neighbor] = level + 1
                queue.append(neighbor)
            }
        }
        return result
    }

    private func drawEdges(context: inout GraphicsContext, positions: [String: CGPoint]) {
        for edge in edges {
            guard let start = positions[edge.firstNodeID],
                  let end = positions[edge.secondNodeID] else { continue }

            let isRelayPath = relayEdgeIDs.contains(edge.id)
            let isHoveredEdge = monitor.hoveredTopologyNodeID.map {
                edge.firstNodeID == $0 || edge.secondNodeID == $0
            } ?? false
            let isDimmed = monitor.hoveredTopologyNodeID != nil && !isHoveredEdge
            let path = curvedPath(from: start, to: end)

            if isRelayPath && !isDimmed {
                context.stroke(
                    path,
                    with: .color(.orange.opacity(0.16)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
            }
            context.stroke(
                path,
                with: .color(edgeColor(isRelayPath: isRelayPath, isDimmed: isDimmed)),
                style: StrokeStyle(
                    lineWidth: isRelayPath ? 2.2 : 1.1,
                    lineCap: .round,
                    dash: isRelayPath ? [] : [3, 3]
                )
            )

            if isHoveredEdge {
                let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 7)
                context.draw(
                    Text("\(edge.latencyMS) ms")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundColor(isRelayPath ? .orange : .secondary),
                    at: midpoint
                )
            }
        }
    }

    private func curvedPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let control = CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2 + min(16, abs(end.x - start.x) * 0.08)
        )
        path.addQuadCurve(to: end, control: control)
        return path
    }

    private func edgeColor(isRelayPath: Bool, isDimmed: Bool) -> Color {
        if isDimmed { return .secondary.opacity(0.09) }
        if isRelayPath { return .orange.opacity(0.9) }
        return .blue.opacity(0.34)
    }

    private func hitTestNode(at location: CGPoint, positions: [String: CGPoint]) -> String? {
        let halfWidth: CGFloat = 43
        let halfHeight: CGFloat = 12

        return nodes
            .compactMap { node -> (id: String, distance: CGFloat)? in
                guard let center = positions[node.nodeID] else { return nil }
                let dx = location.x - center.x
                let dy = location.y - center.y
                guard abs(dx) <= halfWidth, abs(dy) <= halfHeight else { return nil }
                return (node.nodeID, hypot(dx, dy))
            }
            .min { $0.distance < $1.distance }?
            .id
    }

    private func detailPosition(for nodePosition: CGPoint, in size: CGSize) -> CGPoint {
        let cardHalfWidth: CGFloat = 88
        let x = min(max(nodePosition.x, cardHalfWidth), size.width - cardHalfWidth)
        let showAbove = nodePosition.y > size.height / 2
        let proposedY = nodePosition.y + (showAbove ? -62 : 62)
        return CGPoint(x: x, y: min(max(proposedY, 42), size.height - 42))
    }

    private func route(for node: TopologyNode) -> RouteInfo? {
        let nodeIP = normalizedIP(node.ipv4)
        return monitor.routes.first { normalizedIP($0.ipv4) == nodeIP }
    }

    private func normalizedIP(_ value: String) -> String {
        value.split(separator: "/").first.map(String.init) ?? value
    }
}

private struct CompactTopologyNode: View {
    let node: TopologyNode
    let isLocal: Bool
    let isRelayed: Bool
    let isHovered: Bool

    private var color: Color {
        if isLocal { return .green }
        if isRelayed { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(node.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(width: 86, height: 24)
        .background(Color.primary.opacity(isHovered ? 0.09 : 0.055))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(isHovered ? 0.9 : 0.42), lineWidth: isHovered ? 1.5 : 0.8)
        }
        .shadow(color: color.opacity(isHovered ? 0.22 : 0), radius: 5)
    }
}

private struct TopologyNodeDetail: View {
    let node: TopologyNode
    let route: RouteInfo?
    let isLocal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(node.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(node.ipv4)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Text(connectionDescription)
                Text("· \(node.directPeers.count) 个直连邻居")
            }
            .font(.caption2)
            .foregroundStyle(route?.isRelayed == true ? Color.orange : Color.secondary)
        }
        .padding(8)
        .frame(width: 176, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private var connectionDescription: String {
        if isLocal { return "本机" }
        guard let route else { return "路径未知" }
        if route.isRelayed {
            return "经 \(route.nextHopHostname) · \(route.pathLatency) ms"
        }
        return "直连 · \(route.pathLatency) ms"
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).foregroundStyle(.secondary)
        }
    }
}
