import Foundation
import SwiftUI

enum ServiceHealth: Equatable {
    case checking
    case running
    case degraded
    case stopped
    case notInstalled

    var title: String {
        switch self {
        case .checking: return "正在检查"
        case .running: return "运行正常"
        case .degraded: return "服务异常"
        case .stopped: return "已停止"
        case .notInstalled: return "未安装"
        }
    }

    var detail: String {
        switch self {
        case .checking: return "正在获取 EasyTier 状态"
        case .running: return "EasyTier 服务和 RPC 均可用"
        case .degraded: return "服务已运行，但无法读取网络状态"
        case .stopped: return "EasyTier 系统服务当前未运行"
        case .notInstalled: return "未找到 EasyTier 系统服务"
        }
    }

    var symbolName: String {
        switch self {
        case .checking: return "circle.dotted"
        case .running: return "network"
        case .degraded: return "exclamationmark.triangle.fill"
        case .stopped: return "pause.circle.fill"
        case .notInstalled: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .checking: return .secondary
        case .running: return .green
        case .degraded: return .orange
        case .stopped: return .red
        case .notInstalled: return .secondary
        }
    }
}

struct Peer: Codable, Identifiable, Equatable, Sendable {
    let cidr: String
    let ipv4: String
    let hostname: String
    let cost: String
    let latMS: String
    let lossRate: String
    let rxBytes: String
    let txBytes: String
    let tunnelProto: String
    let natType: String
    let id: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case cidr, ipv4, hostname, cost, id, version
        case latMS = "lat_ms"
        case lossRate = "loss_rate"
        case rxBytes = "rx_bytes"
        case txBytes = "tx_bytes"
        case tunnelProto = "tunnel_proto"
        case natType = "nat_type"
    }

    var isLocal: Bool { cost.caseInsensitiveCompare("Local") == .orderedSame }
    var isRelay: Bool { cost.lowercased().contains("relay") }

    var connectionLabel: String {
        if isLocal { return "本机" }
        if isRelay { return "中继" }
        return "直连"
    }

    var connectionSymbol: String {
        if isLocal { return "laptopcomputer" }
        if isRelay { return "arrow.triangle.branch" }
        return "bolt.horizontal.fill"
    }

    var numericLatency: Double? { Double(latMS) }
}

struct ServiceSnapshot: Equatable, Sendable {
    var isInstalled = false
    var isRunning = false
    var pid: Int?
    var peers: [Peer] = []
    var topologyNodes: [TopologyNode] = []
    var routes: [RouteInfo] = []
    var cliPath: String?
    var errorMessage: String?
    var topologyError: String?
}

struct TopologyNode: Codable, Identifiable, Equatable, Sendable {
    let nodeID: String
    let hostname: String
    let ipv4: String
    let directPeers: [DirectPeer]

    var id: String { nodeID }

    var displayName: String {
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHostname.isEmpty, trimmedHostname != "-" {
            return trimmedHostname
        }

        let address = ipv4.split(separator: "/").first.map(String.init) ?? ""
        if !address.isEmpty, address != "-" {
            return address
        }

        let suffix = String(nodeID.suffix(6))
        return suffix.isEmpty ? "未知节点" : "节点 \(suffix)"
    }

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case hostname, ipv4
        case directPeers = "direct_peers"
    }
}

struct DirectPeer: Codable, Equatable, Sendable {
    let nodeID: String
    let hostname: String
    let ipv4: String
    let latencyMS: Int

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case hostname, ipv4
        case latencyMS = "latency_ms"
    }
}

struct RouteInfo: Codable, Equatable, Sendable {
    let ipv4: String
    let hostname: String
    let nextHopIPv4: String
    let nextHopHostname: String
    let pathLength: Int
    let pathLatency: Int

    enum CodingKeys: String, CodingKey {
        case ipv4, hostname
        case nextHopIPv4 = "next_hop_ipv4"
        case nextHopHostname = "next_hop_hostname"
        case pathLength = "path_len"
        case pathLatency = "path_latency"
    }

    var isRelayed: Bool { pathLength > 1 }
}

struct TopologyEdge: Identifiable, Equatable, Sendable {
    let firstNodeID: String
    let secondNodeID: String
    let latencyMS: Int

    var id: String { [firstNodeID, secondNodeID].sorted().joined(separator: "|") }
}

enum TopologySanitizer {
    /// `peer-center` can temporarily retain incomplete or stale global nodes.
    /// The local `peer` response is the source of truth for currently reachable
    /// nodes shown by this status application.
    static func currentNodes(_ nodes: [TopologyNode], activePeers: [Peer]) -> [TopologyNode] {
        let activeIDs = Set(activePeers.map(\.id))
        let validNodes = nodes.filter { node in
            let hostname = node.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
            return activeIDs.contains(node.nodeID) && !hostname.isEmpty && hostname != "-"
        }
        let validIDs = Set(validNodes.map(\.nodeID))

        return validNodes.map { node in
            TopologyNode(
                nodeID: node.nodeID,
                hostname: node.hostname,
                ipv4: node.ipv4,
                directPeers: node.directPeers.filter { validIDs.contains($0.nodeID) }
            )
        }
    }
}

enum ServiceControlAction: String, Sendable {
    case start
    case stop
    case restart

    var progressTitle: String {
        switch self {
        case .start: return "正在启动…"
        case .stop: return "正在停止…"
        case .restart: return "正在重启…"
        }
    }
}

enum PanelSection: String, CaseIterable, Identifiable, Sendable {
    case nodes
    case topology

    var id: String { rawValue }
    var title: String { self == .nodes ? "节点" : "拓扑" }
}
