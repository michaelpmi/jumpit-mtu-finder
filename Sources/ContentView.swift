import SwiftUI

struct ContentView: View {
    @StateObject private var prober = MTUProber()
    @FocusState private var hostFocused: Bool
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inputCard
                    resultCard
                    if !prober.log.isEmpty { logCard }
                    footer
                }
                .padding(20)
            }
        }
        .frame(minWidth: 540, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color.jumpitBrand)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [.jumpitBrand, .jumpitGold],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 46, height: 46)
                .overlay(
                    Image(systemName: "ruler")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .jumpitBrand.opacity(0.35), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("JumpIT")
                        .font(.title2.bold())
                        .foregroundStyle(LinearGradient(colors: [.jumpitBrand, .jumpitGold],
                                                        startPoint: .leading, endPoint: .trailing))
                    Text("MTU Finder")
                        .font(.title2.weight(.semibold))
                }
                Text("Findet die größte fragmentierungsfreie Paketgröße")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: footer (brand)

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [.jumpitBrand, .jumpitGold],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 8)
            Text("JumpIT Netzwerk Service · jumpit.eu")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: input

    private var inputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ziel")
                    .font(.headline)

                HStack {
                    TextField("Host oder IP (z. B. Gateway, 1.1.1.1, server.example.com)",
                              text: $prober.host)
                        .textFieldStyle(.roundedBorder)
                        .focused($hostFocused)
                        .disabled(prober.isRunning)
                        .onSubmit { if !prober.isRunning { prober.start() } }
                    Button("Gateway") { prober.useGateway() }
                        .disabled(prober.isRunning)
                        .help("Default-Gateway dieses Macs einsetzen")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Verbindungstyp")
                        .font(.subheadline.weight(.medium))
                    Picker("Verbindungstyp", selection: $prober.mode) {
                        ForEach(ConnectionMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(prober.isRunning)
                    Text(modeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Jumbo-Frames testen (bis MTU 9000)", isOn: $prober.allowJumbo)
                    .disabled(prober.isRunning)
                    .help("Nur sinnvoll im LAN mit Jumbo-fähigen Switches/NICs")

                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Interface", selection: Binding(
                            get: { prober.boundInterface ?? "" },
                            set: { prober.boundInterface = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Automatisch (Routing)").tag("")
                            ForEach(prober.interfaces) { i in
                                Text(i.label).tag(i.name)
                            }
                        }
                        .disabled(prober.isRunning)

                        Text("Bindet die Pings an ein festes Interface (ping -b) — z. B. um gezielt durch einen Tunnel (utunX) statt über das Standard-Routing zu messen. Das Ziel muss über dieses Interface erreichbar sein.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button { prober.refreshInterfaces() } label: {
                            Label("Interfaces aktualisieren", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(prober.isRunning)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Erweitert: Interface-Bindung")
                        .font(.subheadline.weight(.medium))
                }

                HStack(spacing: 16) {
                    Label("\(prober.localInterface.isEmpty ? "—" : prober.localInterface)",
                          systemImage: "network")
                    Label("lokale MTU \(prober.localMTU)", systemImage: "rectangle.connected.to.line.below")
                    if let b = prober.boundInterface {
                        Label("gebunden an \(b)", systemImage: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(Color.jumpitBrand)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    if prober.isRunning {
                        Button(role: .cancel) { prober.cancel() } label: {
                            Label("Abbrechen", systemImage: "stop.fill")
                        }
                        ProgressView().controlSize(.small).padding(.leading, 4)
                    } else {
                        Button { prober.start() } label: {
                            Label("MTU ermitteln", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(prober.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: result

    private var resultCard: some View {
        Card {
            if let err = prober.errorText {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.jumpitWarn)
                    Text(err).font(.callout)
                }
            } else if let mtu = prober.resultMTU {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Optimale MTU")
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(mtu)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(verdict(mtu, prober.mode).color)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bytes")
                                .foregroundStyle(.secondary)
                            Text("Payload \(mtu - kIPICMPOverhead) + 28 Header")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: verdict(mtu, prober.mode).icon)
                            .foregroundStyle(verdict(mtu, prober.mode).color)
                        Text(verdict(mtu, prober.mode).text)
                    }
                    .font(.callout)

                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow {
                            Text("Sonden").foregroundStyle(.secondary)
                            Text("\(prober.probeCount)")
                        }
                        if prober.mode == .vpn {
                            GridRow(alignment: .top) {
                                Text("Tunnel-Overhead").foregroundStyle(.secondary)
                                Text(overheadText(mtu))
                            }
                        }
                        GridRow(alignment: .top) {
                            Text("Setzen mit").foregroundStyle(.secondary)
                            Text(verbatim: recommendation(mtu, prober.mode))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.callout)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "ruler.fill").foregroundStyle(.secondary)
                    Text("Noch keine Messung. Ziel wählen und MTU ermitteln drücken.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: log

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mess-Sonden")
                    .font(.headline)
                ForEach(prober.log) { e in
                    HStack(spacing: 10) {
                        Image(systemName: e.fits ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(e.fits ? Color.jumpitOK : Color.jumpitDown)
                        Text("MTU \(e.mtu)")
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                        Text("\(e.payload) B Payload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Text(e.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: interpretation

    private struct Verdict { let text: String; let color: Color; let icon: String }

    private var modeHint: String {
        switch prober.mode {
        case .auto:   return "Bewertet die gemessene MTU automatisch nach typischen Bereichen."
        case .direct: return "Ohne Tunnel erwartet: 1500 (Ethernet) bzw. 1492 (PPPoE/DSL)."
        case .vpn:    return "Im Tunnel ist eine reduzierte MTU normal — zeigt Overhead & Protokoll-Tipp."
        }
    }

    /// Overhead of the measured MTU against a 1500-byte Ethernet underlay + likely protocol.
    private func overheadText(_ mtu: Int) -> String {
        let oh = max(0, kEthernetMTU - mtu)
        return "\(oh) B ggü. 1500  —  \(protocolHint(oh))"
    }

    private func protocolHint(_ overhead: Int) -> String {
        switch overhead {
        case 0:        return "kein Overhead (Traffic evtl. nicht im Tunnel)"
        case 1...12:   return "PPPoE/DSL (8 B)"
        case 13...28:  return "GRE / IP-in-IP"
        case 29...48:  return "L2TP / IPsec (Transport)"
        case 49...64:  return "WireGuard über IPv4 (60 B) oder OpenVPN"
        case 65...84:  return "WireGuard über IPv6 (80 B)"
        case 85...140: return "IPsec ESP oder verschachtelte Tunnel"
        default:       return "ungewöhnlich hoher Overhead — Pfad prüfen"
        }
    }

    private func recommendation(_ mtu: Int, _ mode: ConnectionMode) -> String {
        switch mode {
        case .vpn:
            return "WireGuard:  MTU = \(mtu)   (in [Interface])\n"
                 + "sonst:      sudo ifconfig <utunX> mtu \(mtu)"
        default:
            return "sudo networksetup -setMTU <Dienst> \(mtu)"
        }
    }

    private func verdict(_ mtu: Int, _ mode: ConnectionMode) -> Verdict {
        let green  = "checkmark.seal.fill"
        let warn   = "exclamationmark.triangle.fill"
        let info   = "info.circle.fill"
        let bad    = "exclamationmark.octagon.fill"

        switch mode {
        case .vpn:
            // Inside a tunnel a reduced MTU is the expected, healthy case.
            switch mtu {
            case 1492...:
                return Verdict(text: "Ungewöhnlich hoch für VPN — läuft der Traffic wirklich durch den Tunnel?",
                               color: .jumpitGold, icon: info)
            case 1380..<1492:
                return Verdict(text: "Normal für VPN. Optimaler Tunnel-Wert für diese Verbindung.",
                               color: .jumpitOK, icon: green)
            case 1280..<1380:
                return Verdict(text: "Konservativer Tunnel — funktioniert, aber etwas Durchsatz geht verloren.",
                               color: .jumpitOK, icon: green)
            default:
                return Verdict(text: "Sehr niedrig — verschachtelte Tunnel? Pfad prüfen.",
                               color: .jumpitWarn, icon: warn)
            }

        case .direct:
            // No VPN expected → anything well below the link MTU is suspicious.
            switch mtu {
            case 1500...:
                return Verdict(text: "Ethernet-Standard — voller Durchsatz, keine Fragmentierung.",
                               color: .jumpitOK, icon: green)
            case 1492..<1500:
                return Verdict(text: "Typisch für PPPoE/DSL. Optimal für diese Leitung.",
                               color: .jumpitOK, icon: green)
            case 1280..<1492:
                return Verdict(text: "Niedriger als ohne VPN erwartet — Tunnel oder Drosselung im Pfad?",
                               color: .jumpitWarn, icon: warn)
            default:
                return Verdict(text: "Sehr niedrig für eine direkte Verbindung — Pfad prüfen.",
                               color: .jumpitDown, icon: bad)
            }

        case .auto:
            switch mtu {
            case 1500...:
                return Verdict(text: "Ethernet-Standard — voller Durchsatz, keine Fragmentierung.",
                               color: .jumpitOK, icon: green)
            case 1492..<1500:
                return Verdict(text: "Typisch für PPPoE/DSL. Optimal für diese Leitung.",
                               color: .jumpitOK, icon: green)
            case 1400..<1492:
                return Verdict(text: "Reduziert — meist Tunnel/VPN (z. B. WireGuard, IPsec, PPPoE-Overhead).",
                               color: .jumpitGold, icon: warn)
            case 1280..<1400:
                return Verdict(text: "Niedrig — verschachtelte Tunnel oder konservatives VPN.",
                               color: .jumpitWarn, icon: warn)
            default:
                return Verdict(text: "Sehr niedrig — ungewöhnlich, Pfad prüfen.",
                               color: .jumpitDown, icon: bad)
            }
        }
    }
}

// MARK: - JumpIT brand palette (from jumpit.eu)

extension Color {
    static let jumpitBrand = Color(red: 0xF1/255, green: 0x9A/255, blue: 0x3A/255) // #f19a3a
    static let jumpitGold  = Color(red: 0xF4/255, green: 0xBF/255, blue: 0x36/255) // #f4bf36
    static let jumpitOK    = Color(red: 0x1F/255, green: 0x9D/255, blue: 0x5B/255) // #1f9d5b
    static let jumpitWarn  = Color(red: 0xD9/255, green: 0x95/255, blue: 0x18/255) // #d99518
    static let jumpitDown  = Color(red: 0xD4/255, green: 0x48/255, blue: 0x3B/255) // #d4483b
}

/// Lightweight card container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
