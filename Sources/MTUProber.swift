import Foundation
import Combine

// IPv4 header (20) + ICMP header (8) = 28 bytes overhead on top of the ICMP payload.
let kIPICMPOverhead = 28

// Reference MTU of a typical untunneled Ethernet underlay — basis for the overhead estimate.
let kEthernetMTU = 1500

enum ConnectionMode: String, CaseIterable, Identifiable {
    case auto, direct, vpn
    var id: String { rawValue }
    var labelKey: String { "mode.\(rawValue)" }
    var hintKey: String  { "mode.\(rawValue).hint" }
}

/// Language-neutral progress state — the view renders the localized text.
enum ProbeStatus: Equatable {
    case ready
    case starting(host: String)
    case checking(host: String)
    case testing(mtu: Int, payload: Int)
    case pathTooSmall(mtu: Int)
    case cancelled
    case done(host: String, mtu: Int)
    case noAnswer
}

/// Language-neutral error state — the view renders the localized text.
enum ProbeError: Equatable {
    case emptyHost
    case boundUnreachable(host: String, iface: String)
    case resolve(host: String)
    case icmpBlocked(host: String)
}

enum PingOutcome {
    case ok            // reply received → payload fits the whole path
    case tooLong       // local "sendto: Message too long" → exceeds local interface MTU
    case noReply       // timeout / frag-needed / loss → does not fit (retryable)
    case error         // deterministic failure: no route, DNS, bad/invalid interface
}

/// Thread-safe holder so a Task cancellation can terminate the in-flight ping process.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Register the process; returns false if cancellation already happened.
    func adopt(_ p: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        process = p
        return true
    }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }
}

struct ProbeLogEntry: Identifiable {
    let id = UUID()
    let mtu: Int
    let payload: Int
    let fits: Bool
    let outcome: PingOutcome
}

struct InterfaceInfo: Identifiable, Hashable {
    let name: String          // e.g. "en1", "utun1"
    let mtu: Int
    var id: String { name }
    var isTunnel: Bool { name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("gif") }
    var label: String { "\(name) · MTU \(mtu)\(isTunnel ? " · Tunnel" : "")" }
}

@MainActor
final class MTUProber: ObservableObject {

    @Published var host: String = ""
    @Published var allowJumbo: Bool = false
    @Published var mode: ConnectionMode = .auto

    @Published var isRunning: Bool = false
    @Published var status: ProbeStatus = .ready
    @Published var currentMTU: Int? = nil          // MTU currently being probed
    @Published var resultMTU: Int? = nil           // final best MTU
    @Published var error: ProbeError? = nil
    @Published var log: [ProbeLogEntry] = []

    @Published var localInterface: String = ""
    @Published var localMTU: Int = 1500
    @Published var probeCount: Int = 0

    // Advanced: bind probes to a specific interface (nil = automatic routing).
    @Published var interfaces: [InterfaceInfo] = []
    @Published var boundInterface: String? = nil

    private var task: Task<Void, Never>? = nil

    init() {
        let info = NetworkInfo.primary()
        self.localInterface = info.interface
        self.localMTU = info.mtu
        self.host = info.gateway ?? "1.1.1.1"
        self.interfaces = NetworkInfo.allInterfaces()
    }

    func refreshInterfaces() {
        interfaces = NetworkInfo.allInterfaces()
        // drop a stale binding if the interface disappeared
        if let b = boundInterface, !interfaces.contains(where: { $0.name == b }) {
            boundInterface = nil
        }
    }

    func useGateway() {
        if let gw = NetworkInfo.primary().gateway { host = gw }
    }

    func cancel() {
        task?.cancel()
    }

    func start() {
        guard !isRunning else { return }
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            error = .emptyHost
            return
        }
        // reset state
        log.removeAll()
        resultMTU = nil
        error = nil
        currentMTU = nil
        probeCount = 0
        isRunning = true
        status = .starting(host: target)

        // Upper bound = MTU of the interface the probes actually use. With DF set,
        // a payload above the local interface MTU can only return "Message too long",
        // so the interface MTU is the real ceiling (bound interface if set, else default).
        let ifaceMTU: Int = {
            if let b = boundInterface,
               let i = interfaces.first(where: { $0.name == b }), i.mtu > 0 {
                return i.mtu
            }
            return localMTU > 0 ? localMTU : 1500
        }()
        // Without jumbo, don't bother probing above 1500; with jumbo, go up to the
        // interface MTU (only meaningful if the interface itself supports >1500).
        let hiMTU = allowJumbo ? ifaceMTU : min(ifaceMTU, 1500)
        let loMTU = min(576, hiMTU)   // classic IPv4 safe floor, clamped below the ceiling

        task = Task { [weak self] in
            await self?.run(host: target, loMTU: loMTU, hiMTU: hiMTU)
        }
    }

    private func run(host: String, loMTU: Int, hiMTU: Int) async {
        defer {
            isRunning = false
            currentMTU = nil
        }

        // 0) reachability baseline with a tiny packet (retry on loss, like the probes)
        status = .checking(host: host)
        var baseline = await probe(host: host, payload: 64)
        var bTries = 0
        while baseline == .noReply && bTries < 2 {
            if Task.isCancelled { status = .cancelled; return }
            bTries += 1
            baseline = await probe(host: host, payload: 64)
        }
        if Task.isCancelled { status = .cancelled; return }
        if baseline != .ok {
            if let b = boundInterface {
                error = .boundUnreachable(host: host, iface: b)
            } else if baseline == .error {
                error = .resolve(host: host)
            } else {
                error = .icmpBlocked(host: host)
            }
            status = .noAnswer
            return
        }

        // 1) does the maximum already work? (common case: full 1500)
        var lo = loMTU              // known to NOT necessarily fit yet — verified below
        var hi = hiMTU

        // ensure lo fits; if even 576 fails on the path, walk down toward baseline
        if await probeMTU(host: host, mtu: lo) == false {
            // path can't even do 576 — fall back to whatever the baseline payload implies
            status = .pathTooSmall(mtu: lo)
            lo = 64 + kIPICMPOverhead
        }
        if Task.isCancelled { status = .cancelled; return }

        if await probeMTU(host: host, mtu: hi) {
            finish(best: hi, host: host)
            return
        }
        if Task.isCancelled { status = .cancelled; return }

        // 2) binary search for the largest MTU that fits, in (lo, hi)
        var best = lo
        while lo <= hi {
            if Task.isCancelled { status = .cancelled; return }
            let mid = (lo + hi) / 2
            if await probeMTU(host: host, mtu: mid) {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        finish(best: best, host: host)
    }

    private func finish(best: Int, host: String) {
        resultMTU = best
        status = .done(host: host, mtu: best)
    }

    /// Probe a full MTU value (converts to ICMP payload). Returns true if it fits.
    private func probeMTU(host: String, mtu: Int) async -> Bool {
        let payload = max(0, mtu - kIPICMPOverhead)
        currentMTU = mtu
        status = .testing(mtu: mtu, payload: payload)

        var outcome = await probe(host: host, payload: payload)
        // retry only on no-reply (could be packet loss); "too long" is deterministic.
        var retries = 0
        while outcome == .noReply && retries < 2 {
            if Task.isCancelled { return false }
            retries += 1
            outcome = await probe(host: host, payload: payload)
        }

        let fits = (outcome == .ok)
        probeCount += 1
        log.insert(ProbeLogEntry(mtu: mtu, payload: payload, fits: fits, outcome: outcome), at: 0)
        return fits
    }

    /// Run a single ping with the don't-fragment bit set, optionally bound to an interface.
    /// Cancelling the Task terminates the in-flight ping process.
    private func probe(host: String, payload: Int) async -> PingOutcome {
        let iface = boundInterface
        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<PingOutcome, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: MTUProber.runPing(host: host, payload: payload,
                                                             boundInterface: iface, box: box))
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    nonisolated static func runPing(host: String, payload: Int,
                                    boundInterface: String? = nil,
                                    box: ProcessBox? = nil) -> PingOutcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -c 1: one packet, -t 2: give up after 2s, -D: don't fragment, -s: payload bytes
        var args = ["-c", "1", "-t", "2", "-D", "-s", "\(payload)"]
        // -b boundif: send through a specific interface (bypasses the routing table)
        if let iface = boundInterface, !iface.isEmpty {
            args += ["-b", iface]
        }
        args.append(host)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        // Register with the cancellation box; bail out if already cancelled.
        if let box = box, !box.adopt(p) { return .noReply }
        do {
            try p.run()
        } catch {
            return .error
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = (String(data: data, encoding: .utf8) ?? "").lowercased()

        if out.contains("message too long") { return .tooLong }
        // Deterministic failures — retrying won't help, and they need a clearer message.
        if out.contains("no route to host") || out.contains("cannot resolve")
            || out.contains("unknown host") || out.contains("bad interface")
            || out.contains("no such") || out.contains("can't assign")
            || out.contains("not permitted") {
            return .error
        }
        return p.terminationStatus == 0 ? .ok : .noReply
    }
}
