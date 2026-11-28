// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// The Mac's own address on the local network, for telling another device where to connect.
nonisolated enum LocalNetwork {
    /// One address on one interface, as `getifaddrs` gives them.
    struct Candidate: Equatable {
        let interface: String
        let address: String
    }

    /// The address to show: an IPv4 one on a Wi-Fi or Ethernet interface (`en0`, `en1`, ...),
    /// never loopback or link-local (169.254...), which no other device can reach.
    static func best(from candidates: [Candidate]) -> String? {
        candidates
            .filter { $0.interface.hasPrefix("en") }
            .filter { !$0.address.hasPrefix("127.") && !$0.address.hasPrefix("169.254.") }
            .sorted { $0.interface < $1.interface }
            .first?.address
    }

    /// The IPv4 addresses of this Mac's interfaces.
    static func candidates() -> [Candidate] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var found: [Candidate] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            if getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                found.append(Candidate(interface: String(cString: entry.ifa_name), address: String(cString: host)))
            }
        }
        return found
    }

    /// This Mac's address on the local network, if it has one.
    static var address: String? { best(from: candidates()) }

    /// The name other devices on the network can reach this Mac by, such as `Mac-mini.local`.
    static var hostName: String { ProcessInfo.processInfo.hostName }
}
