import Foundation
import Testing
@testable import EasyTierMenuBar

@Suite("EasyTier models")
struct ModelsTests {
    @Test("Peer JSON decoding and relay classification")
    func peerJSONDecodingAndConnectionType() throws {
        let json = #"""
        [{
          "cidr":"10.1.1.2/24","ipv4":"10.1.1.2","hostname":"node-a",
          "cost":"relay(2)","lat_ms":"32.50","loss_rate":"0.0%",
          "rx_bytes":"1 kB","tx_bytes":"2 kB","tunnel_proto":"tcp",
          "nat_type":"Symmetric","id":"42","version":"2.6.4"
        }]
        """#

        let peers = try JSONDecoder().decode([Peer].self, from: Data(json.utf8))
        #expect(peers.count == 1)
        #expect(peers[0].isRelay)
        #expect(peers[0].connectionLabel == "中继")
        #expect(peers[0].numericLatency == 32.5)
    }

    @Test("Local peer classification")
    func localPeerClassification() {
        let peer = Peer(
            cidr: "10.1.1.1/24", ipv4: "10.1.1.1", hostname: "mac",
            cost: "Local", latMS: "-", lossRate: "-", rxBytes: "-",
            txBytes: "-", tunnelProto: "-", natType: "Unknown",
            id: "1", version: "2.6.4"
        )
        #expect(peer.isLocal)
        #expect(peer.connectionLabel == "本机")
    }

    @Test("Topology and route JSON decoding")
    func topologyAndRouteDecoding() throws {
        let topologyJSON = #"""
        [{
          "node_id":"1","hostname":"local","ipv4":"10.1.1.1/24",
          "direct_peers":[{
            "node_id":"2","hostname":"relay","ipv4":"10.1.1.2/24","latency_ms":12
          }]
        }]
        """#
        let routeJSON = #"""
        [{
          "ipv4":"10.1.1.3/24","hostname":"target",
          "next_hop_ipv4":"10.1.1.2/24","next_hop_hostname":"relay",
          "path_len":2,"path_latency":30
        }]
        """#

        let nodes = try JSONDecoder().decode([TopologyNode].self, from: Data(topologyJSON.utf8))
        let routes = try JSONDecoder().decode([RouteInfo].self, from: Data(routeJSON.utf8))
        #expect(nodes[0].directPeers[0].latencyMS == 12)
        #expect(routes[0].isRelayed)
        #expect(routes[0].nextHopHostname == "relay")
    }

    @Test("Topology node falls back to IP when hostname is empty")
    func topologyNodeDisplayNameFallback() {
        let node = TopologyNode(
            nodeID: "123456789",
            hostname: "   ",
            ipv4: "10.1.1.9/24",
            directPeers: []
        )
        #expect(node.displayName == "10.1.1.9")
    }

    @Test("Topology excludes incomplete nodes not present in local peers")
    func topologyFiltersIncompleteGlobalNodes() {
        let activePeer = Peer(
            cidr: "10.1.1.1/24", ipv4: "10.1.1.1", hostname: "local",
            cost: "Local", latMS: "-", lossRate: "-", rxBytes: "-",
            txBytes: "-", tunnelProto: "-", natType: "Unknown",
            id: "1", version: "2.6.4"
        )
        let nodes = [
            TopologyNode(
                nodeID: "1", hostname: "local", ipv4: "10.1.1.1/24",
                directPeers: [
                    DirectPeer(nodeID: "2", hostname: "", ipv4: "", latencyMS: 30)
                ]
            ),
            TopologyNode(
                nodeID: "2", hostname: "", ipv4: "", directPeers: []
            )
        ]

        let filtered = TopologySanitizer.currentNodes(nodes, activePeers: [activePeer])
        #expect(filtered.map(\.nodeID) == ["1"])
        #expect(filtered[0].directPeers.isEmpty)
    }
}
