import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class ServiceMonitor: ObservableObject {
    @Published private(set) var health: ServiceHealth = .checking
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var topologyNodes: [TopologyNode] = []
    @Published private(set) var routes: [RouteInfo] = []
    @Published private(set) var pid: Int?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var topologyError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var currentAction: ServiceControlAction?
    @Published var hoveredTopologyNodeID: String?
    @Published var nodesExpanded = true
    @Published var topologyExpanded = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var launchAtLoginError: String?

    let serviceLabel = "easytier"
    let rpcPortal = "127.0.0.1:15888"

    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isPanelVisible = false
    private var expansionAnimationDeadline = Date.distantPast

    var localPeer: Peer? { peers.first(where: \.isLocal) }
    var remotePeers: [Peer] { peers.filter { !$0.isLocal } }

    var localTopologyNodeID: String? {
        guard let localIP = localPeer?.ipv4 else { return nil }
        return topologyNodes.first { normalizedIP($0.ipv4) == localIP }?.nodeID
    }

    var topologyEdges: [TopologyEdge] {
        var edges: [String: TopologyEdge] = [:]
        for node in topologyNodes {
            for peer in node.directPeers where peer.nodeID != node.nodeID {
                let ids = [node.nodeID, peer.nodeID].sorted()
                let key = ids.joined(separator: "|")
                let latency = edges[key].map { min($0.latencyMS, peer.latencyMS) } ?? peer.latencyMS
                edges[key] = TopologyEdge(
                    firstNodeID: ids[0],
                    secondNodeID: ids[1],
                    latencyMS: latency
                )
            }
        }
        return edges.values.sorted { $0.id < $1.id }
    }

    var relayedNodeIDs: Set<String> {
        let relayedIPs = Set(routes.filter(\.isRelayed).map { normalizedIP($0.ipv4) })
        return Set(topologyNodes.filter { relayedIPs.contains(normalizedIP($0.ipv4)) }.map(\.nodeID))
    }

    var relayEdgeIDs: Set<String> {
        guard let localID = localTopologyNodeID else { return [] }
        var result: Set<String> = []

        for route in routes where route.isRelayed {
            guard let target = topologyNode(matchingIP: route.ipv4),
                  let nextHop = topologyNode(matchingIP: route.nextHopIPv4) else { continue }

            result.insert(edgeID(localID, nextHop.nodeID))
            if let path = shortestPath(from: nextHop.nodeID, to: target.nodeID, excluding: [localID]) {
                for pair in zip(path, path.dropFirst()) {
                    result.insert(edgeID(pair.0, pair.1))
                }
            }
        }
        return result
    }

    func relayDescription(for peer: Peer) -> String? {
        guard let route = routes.first(where: { normalizedIP($0.ipv4) == peer.ipv4 }),
              route.isRelayed else { return nil }
        return "经 \(route.nextHopHostname) 中继"
    }

    init() {
        refreshLaunchAtLoginStatus()
    }

    deinit {
        pollingTask?.cancel()
        refreshTask?.cancel()
    }

    func panelDidAppear() {
        isPanelVisible = true
        refreshLaunchAtLoginStatus()
        startPolling()
    }

    func refreshOnLaunch() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.refreshTask = nil
        }
    }

    func panelDidDisappear() {
        isPanelVisible = false
        hoveredTopologyNodeID = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func refreshNow() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            self?.refreshTask = nil
        }
    }

    func start() {
        perform(.start)
    }

    func stop() {
        perform(.stop)
    }

    func restart() {
        perform(.restart)
    }

    func toggleNodesExpansion() {
        beginExpansionAnimation()
        nodesExpanded.toggle()
    }

    func toggleTopologyExpansion() {
        beginExpansionAnimation()
        topologyExpanded.toggle()
    }

    var isExpansionAnimating: Bool {
        Date() < expansionAnimationDeadline
    }

    private func beginExpansionAnimation() {
        expansionAnimationDeadline = Date().addingTimeInterval(0.5)
    }

    private func perform(_ action: ServiceControlAction) {
        guard currentAction == nil else { return }
        currentAction = action
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            let service = EasyTierService(serviceLabel: serviceLabel, rpcPortal: rpcPortal)
            let result = await service.perform(action)

            switch result {
            case .success:
                try? await Task.sleep(for: .seconds(1.2))
                if isPanelVisible {
                    await refresh()
                }
            case .failure(let error):
                errorMessage = error.message
            }
            currentAction = nil
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            launchAtLoginError = conciseLoginItemError(error)
        }

        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let service = EasyTierService(serviceLabel: serviceLabel, rpcPortal: rpcPortal)
        let snapshot = await service.snapshot()

        while isExpansionAnimating {
            let remaining = expansionAnimationDeadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            try? await Task.sleep(for: .seconds(remaining))
        }

        pid = snapshot.pid
        peers = snapshot.peers
        topologyNodes = snapshot.topologyNodes
        routes = snapshot.routes
        errorMessage = snapshot.errorMessage
        topologyError = snapshot.topologyError
        lastUpdated = Date()

        if !snapshot.isInstalled {
            health = .notInstalled
        } else if !snapshot.isRunning {
            health = .stopped
        } else if snapshot.errorMessage != nil {
            health = .degraded
        } else {
            health = .running
        }
    }

    private func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginRequiresApproval = false
        case .requiresApproval:
            launchAtLoginEnabled = true
            launchAtLoginRequiresApproval = true
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginError = "macOS 无法找到当前应用的登录项"
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
        }
    }

    private func conciseLoginItemError(_ error: Error) -> String {
        let message = (error as NSError).localizedDescription
        return String(message.prefix(160))
    }

    private func normalizedIP(_ value: String) -> String {
        value.split(separator: "/").first.map(String.init) ?? value
    }

    private func topologyNode(matchingIP ip: String) -> TopologyNode? {
        let target = normalizedIP(ip)
        return topologyNodes.first { normalizedIP($0.ipv4) == target }
    }

    private func edgeID(_ first: String, _ second: String) -> String {
        [first, second].sorted().joined(separator: "|")
    }

    private func shortestPath(from start: String, to target: String, excluding excluded: Set<String>) -> [String]? {
        guard start != target else { return [start] }
        var queue: [[String]] = [[start]]
        var visited = excluded
        visited.insert(start)

        while !queue.isEmpty {
            let path = queue.removeFirst()
            guard let current = path.last,
                  let node = topologyNodes.first(where: { $0.nodeID == current }) else { continue }

            for neighbor in node.directPeers.map(\.nodeID) where !visited.contains(neighbor) {
                let nextPath = path + [neighbor]
                if neighbor == target { return nextPath }
                visited.insert(neighbor)
                queue.append(nextPath)
            }
        }
        return nil
    }
}
