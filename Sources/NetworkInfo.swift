import Foundation

struct NetworkInfo {
    let interface: String
    let mtu: Int
    let gateway: String?

    /// Read the primary interface, its MTU and the default gateway via route/ifconfig.
    static func primary() -> NetworkInfo {
        let route = shell("/sbin/route", ["-n", "get", "default"])
        let iface = route
            .lines.first(where: { $0.contains("interface:") })?
            .split(separator: ":").last?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let gw = route
            .lines.first(where: { $0.contains("gateway:") })?
            .split(separator: ":").last?
            .trimmingCharacters(in: .whitespaces)

        var mtu = 1500
        if !iface.isEmpty {
            let cfg = shell("/sbin/ifconfig", [iface])
            if let mtuTok = cfg.split(separator: " ").drop(while: { $0 != "mtu" }).dropFirst().first,
               let v = Int(mtuTok) {
                mtu = v
            }
        }
        return NetworkInfo(interface: iface, mtu: mtu, gateway: gw)
    }

    /// All UP interfaces that make sense to bind a probe to: physical NICs + tunnels.
    /// Excludes loopback and down interfaces.
    static func allInterfaces() -> [InterfaceInfo] {
        let names = shell("/sbin/ifconfig", ["-l"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map(String.init)

        var result: [InterfaceInfo] = []
        for name in names {
            if name == "lo0" { continue }
            let keep = name.hasPrefix("en") || name.hasPrefix("bridge")
                    || name.hasPrefix("utun") || name.hasPrefix("ipsec")
                    || name.hasPrefix("ppp") || name.hasPrefix("gif")
            guard keep else { continue }

            let cfg = shell("/sbin/ifconfig", [name])
            guard cfg.contains("UP") && cfg.contains("RUNNING") else { continue }
            // Physical NICs can be UP,RUNNING while unplugged; require an active link.
            if name.hasPrefix("en") || name.hasPrefix("bridge") {
                guard cfg.contains("status: active") else { continue }
            }
            let mtu = cfg.split(separator: " ").drop(while: { $0 != "mtu" }).dropFirst().first
                .flatMap { Int($0) } ?? 0
            result.append(InterfaceInfo(name: name, mtu: mtu))
        }
        return result
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private extension String {
    var lines: [String] { split(separator: "\n").map(String.init) }
}
