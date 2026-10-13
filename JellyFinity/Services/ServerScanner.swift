import Darwin
import Foundation

/// A Jellyfin server found on the local network.
struct NearbyServer: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let version: String?
    var id: URL { url }
}

/// Finds Jellyfin servers on the same Wi‑Fi by probing the local subnet's default Jellyfin port.
enum ServerScanner {
    static let ports = [8096]

    static func scan() async -> [NearbyServer] {
        let hosts = candidateHosts()
        NSLog("JellyFinity scanning %d hosts for Jellyfin", hosts.count)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2.5
        config.httpMaximumConnectionsPerHost = 2
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var urls: [URL] = []
        for host in hosts {
            for port in ports {
                if let url = URL(string: "http://\(host):\(port)") { urls.append(url) }
            }
        }
        var found: [NearbyServer] = []
        await withTaskGroup(of: NearbyServer?.self) { group in
            var iterator = urls.makeIterator()
            for _ in 0..<48 {
                guard let url = iterator.next() else { break }
                group.addTask { await probe(url, session: session) }
            }
            for await result in group {
                if let result { found.append(result) }
                if Task.isCancelled { group.cancelAll(); break }
                if let url = iterator.next() { group.addTask { await probe(url, session: session) } }
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func probe(_ base: URL, session: URLSession) async -> NearbyServer? {
        var request = URLRequest(url: base.appendingPathComponent("System/Info/Public"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(PublicSystemInfo.self, from: data),
              info.version != nil || info.serverName != nil else { return nil }
        return NearbyServer(url: base, name: info.serverName ?? base.host() ?? "Jellyfin", version: info.version)
    }

    /// Every address in this device's /24 Wi‑Fi or Ethernet subnet (excluding itself).
    private static func candidateHosts() -> [String] {
        var hosts: [String] = []
        var seenPrefixes = Set<String>()
        for address in localIPv4Addresses() {
            let parts = address.split(separator: ".")
            guard parts.count == 4 else { continue }
            let prefix = parts.prefix(3).joined(separator: ".")
            guard seenPrefixes.insert(prefix).inserted else { continue }
            hosts += (1...254).map { "\(prefix).\($0)" }.filter { $0 != address }
        }
        return hosts
    }

    private static func localIPv4Addresses() -> [String] {
        var result: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            guard status == 0 else { continue }
            let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)
            if !ip.hasPrefix("169.254"), !ip.hasPrefix("127.") { result.append(ip) }
        }
        return result
    }
}
