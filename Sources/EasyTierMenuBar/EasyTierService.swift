import Foundation

struct EasyTierService: Sendable {
    let serviceLabel: String
    let rpcPortal: String

    func snapshot() async -> ServiceSnapshot {
        async let serviceResult = CommandRunner.run(
            "/bin/launchctl",
            arguments: ["print", "system/\(serviceLabel)"]
        )

        let launchctl = await serviceResult
        let installed = isServiceInstalled || launchctl.status == 0
        guard installed else {
            return ServiceSnapshot(isInstalled: false, errorMessage: "找不到 /Library/LaunchDaemons/\(serviceLabel).plist")
        }

        guard launchctl.status == 0 else {
            return ServiceSnapshot(isInstalled: true, isRunning: false)
        }

        let running = value(named: "state", in: launchctl.standardOutput) == "running"
        let pid = value(named: "pid", in: launchctl.standardOutput).flatMap(Int.init)
        guard running else {
            return ServiceSnapshot(isInstalled: true, isRunning: false, pid: pid)
        }

        guard let cliPath = findCLI() else {
            return ServiceSnapshot(
                isInstalled: true,
                isRunning: true,
                pid: pid,
                errorMessage: "未找到 easytier-cli，无法读取节点信息"
            )
        }

        async let peerCommand = CommandRunner.run(
            cliPath,
            arguments: ["--rpc-portal", rpcPortal, "--output", "json", "peer"],
            timeout: 10
        )
        async let topologyCommand = CommandRunner.run(
            cliPath,
            arguments: ["--rpc-portal", rpcPortal, "--output", "json", "peer-center"],
            timeout: 10
        )
        async let routeCommand = CommandRunner.run(
            cliPath,
            arguments: ["--rpc-portal", rpcPortal, "--output", "json", "route"],
            timeout: 10
        )

        let (peerResult, topologyResult, routeResult) = await (peerCommand, topologyCommand, routeCommand)

        guard peerResult.status == 0,
              let data = peerResult.standardOutput.data(using: .utf8) else {
            return ServiceSnapshot(
                isInstalled: true,
                isRunning: true,
                pid: pid,
                cliPath: cliPath,
                errorMessage: conciseError(peerResult.combinedOutput)
            )
        }

        do {
            let peers = try JSONDecoder().decode([Peer].self, from: data)
            let decodedTopologyNodes = decode([TopologyNode].self, from: topologyResult)
            let topologyNodes = decodedTopologyNodes.map {
                TopologySanitizer.currentNodes($0, activePeers: peers)
            }
            let routes = decode([RouteInfo].self, from: routeResult)
            let topologyError: String?
            if decodedTopologyNodes == nil {
                topologyError = "当前 EasyTier 实例未返回全局拓扑信息"
            } else if routes == nil {
                topologyError = "可以显示直连拓扑，但中继路径信息不可用"
            } else {
                topologyError = nil
            }

            return ServiceSnapshot(
                isInstalled: true,
                isRunning: true,
                pid: pid,
                peers: peers,
                topologyNodes: topologyNodes ?? [],
                routes: routes ?? [],
                cliPath: cliPath,
                topologyError: topologyError
            )
        } catch {
            return ServiceSnapshot(
                isInstalled: true,
                isRunning: true,
                pid: pid,
                cliPath: cliPath,
                errorMessage: "EasyTier 返回了无法识别的节点数据"
            )
        }
    }

    func perform(_ action: ServiceControlAction) async -> Result<Void, ServiceActionError> {
        guard serviceLabel.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return .failure(ServiceActionError(message: "服务名称包含不支持的字符"))
        }

        let domainTarget = "system/\(serviceLabel)"
        let plistPath = "/Library/LaunchDaemons/\(serviceLabel).plist"
        let shellCommand: String

        switch action {
        case .start:
            shellCommand = "if /bin/launchctl print \(domainTarget) >/dev/null 2>&1; then " +
                "/bin/launchctl kickstart \(domainTarget); else " +
                "/bin/launchctl bootstrap system \(plistPath); fi"
        case .stop:
            shellCommand = "/bin/launchctl bootout \(domainTarget)"
        case .restart:
            shellCommand = "if /bin/launchctl print \(domainTarget) >/dev/null 2>&1; then " +
                "/bin/launchctl kickstart -k \(domainTarget); else " +
                "/bin/launchctl bootstrap system \(plistPath); fi"
        }

        let script = "do shell script \"\(shellCommand)\" with administrator privileges"
        let result = await CommandRunner.run("/usr/bin/osascript", arguments: ["-e", script], timeout: 60)

        if result.status == 0 {
            return .success(())
        }

        let message = result.combinedOutput
        if message.localizedCaseInsensitiveContains("User canceled") || message.contains("-128") {
            return .failure(ServiceActionError(message: "已取消管理员授权"))
        }
        return .failure(ServiceActionError(message: conciseError(message.isEmpty ? "服务操作执行失败" : message)))
    }

    private var isServiceInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/\(serviceLabel).plist") ||
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/LaunchAgents/\(serviceLabel).plist")
    }

    private func findCLI() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            home + "/.local/bin/easytier-cli",
            "/opt/homebrew/bin/easytier-cli",
            "/usr/local/bin/easytier-cli",
            "/usr/bin/easytier-cli"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func value(named key: String, in launchctlOutput: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^\s*"# + escapedKey + #"\s*=\s*([^\s;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: launchctlOutput,
                range: NSRange(launchctlOutput.startIndex..., in: launchctlOutput)
              ),
              let range = Range(match.range(at: 1), in: launchctlOutput) else {
            return nil
        }
        return String(launchctlOutput[range])
    }

    private func conciseError(_ text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \Character.isNewline)
            .first
            .map(String.init) ?? "未知错误"
        return String(firstLine.prefix(180))
    }

    private func decode<T: Decodable>(_ type: T.Type, from result: CommandResult) -> T? {
        guard result.status == 0,
              let data = result.standardOutput.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct ServiceActionError: Error, Sendable {
    let message: String
}
