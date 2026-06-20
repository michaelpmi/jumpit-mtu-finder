import SwiftUI

struct ContentView: View {
    @StateObject private var prober = MTUProber()
    @FocusState private var hostFocused: Bool
    @State private var showAdvanced = false
    @AppStorage(Lang.storageKey) private var appLang: String = AppLanguage.system.rawValue

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
        .frame(minWidth: 540, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color.jumpitBrand)
        // Changing `appLang` (@AppStorage) re-renders the body; L() then returns the
        // new language because the picker's setter updates Lang.override first.
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
                Text(L("app.tagline"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            languageMenu
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var languageMenu: some View {
        Picker(selection: Binding(
            get: { appLang },
            set: { Lang.apply($0); appLang = $0 }   // set global BEFORE the re-render
        )) {
            ForEach(AppLanguage.allCases) { lang in
                Text(lang.nativeName).tag(lang.rawValue)
            }
        } label: {
            Image(systemName: "globe")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help(L("lang.label"))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [.jumpitBrand, .jumpitGold],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 8)
            Text(verbatim: "JumpIT Netzwerk Service · jumpit.eu")
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
                Text(L("input.target"))
                    .font(.headline)

                HStack {
                    TextField(L("input.host_placeholder"), text: $prober.host)
                        .textFieldStyle(.roundedBorder)
                        .focused($hostFocused)
                        .disabled(prober.isRunning)
                        .onSubmit { if !prober.isRunning { prober.start() } }
                    Button(L("input.gateway")) { prober.useGateway() }
                        .disabled(prober.isRunning)
                        .help(L("input.gateway_help"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("input.conn_type"))
                        .font(.subheadline.weight(.medium))
                    Picker("", selection: $prober.mode) {
                        ForEach(ConnectionMode.allCases) { m in
                            Text(L(m.labelKey)).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(prober.isRunning)
                    .id(appLang)   // rebuild segment labels when the language changes
                    Text(L(prober.mode.hintKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(L("input.jumbo"), isOn: $prober.allowJumbo)
                    .disabled(prober.isRunning)
                    .help(L("input.jumbo_help"))

                DisclosureGroup(isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker(L("adv.title"), selection: Binding(
                            get: { prober.boundInterface ?? "" },
                            set: { prober.boundInterface = $0.isEmpty ? nil : $0 }
                        )) {
                            Text(L("adv.auto_routing")).tag("")
                            ForEach(prober.interfaces) { i in
                                Text(interfaceLabel(i)).tag(i.name)
                            }
                        }
                        .disabled(prober.isRunning)
                        .id(appLang)   // rebuild option labels when the language changes

                        Text(L("adv.hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button { prober.refreshInterfaces() } label: {
                            Label(L("adv.refresh"), systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(prober.isRunning)
                    }
                    .padding(.top, 6)
                } label: {
                    Text(L("adv.title"))
                        .font(.subheadline.weight(.medium))
                }

                HStack(spacing: 16) {
                    Label(prober.localInterface.isEmpty ? "—" : prober.localInterface,
                          systemImage: "network")
                    Label(L("info.local_mtu", prober.localMTU),
                          systemImage: "rectangle.connected.to.line.below")
                    if let b = prober.boundInterface {
                        Label(L("info.bound_to", b), systemImage: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(Color.jumpitBrand)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    if prober.isRunning {
                        Button(role: .cancel) { prober.cancel() } label: {
                            Label(L("btn.cancel"), systemImage: "stop.fill")
                        }
                        ProgressView().controlSize(.small).padding(.leading, 4)
                    } else {
                        Button { prober.start() } label: {
                            Label(L("btn.measure"), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(statusText(prober.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: result

    private var resultCard: some View {
        Card {
            if let err = prober.error {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.jumpitWarn)
                    Text(errorText(err)).font(.callout)
                }
            } else if let mtu = prober.resultMTU {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("result.title"))
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(mtu)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(verdict(mtu, prober.mode).color)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("result.bytes"))
                                .foregroundStyle(.secondary)
                            Text(L("result.payload_header", mtu - kIPICMPOverhead))
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
                            Text(L("result.probes")).foregroundStyle(.secondary)
                            Text(verbatim: "\(prober.probeCount)")
                        }
                        if prober.mode == .vpn {
                            GridRow(alignment: .top) {
                                Text(L("result.tunnel_overhead")).foregroundStyle(.secondary)
                                Text(overheadText(mtu))
                            }
                        }
                        GridRow(alignment: .top) {
                            Text(L("result.set_with")).foregroundStyle(.secondary)
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
                    Text(L("result.empty"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: log

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("log.title"))
                    .font(.headline)
                ForEach(prober.log) { e in
                    HStack(spacing: 10) {
                        Image(systemName: e.fits ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(e.fits ? Color.jumpitOK : Color.jumpitDown)
                        Text(L("log.mtu", e.mtu))
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                        Text(L("log.payload", e.payload))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)
                        Text(logNote(e.outcome))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: localized state rendering

    private func statusText(_ s: ProbeStatus) -> String {
        switch s {
        case .ready:                       return L("status.ready")
        case .starting(let h):             return L("status.starting", h)
        case .checking(let h):             return L("status.checking", h)
        case .testing(let m, let p):       return L("status.testing", m, p)
        case .pathTooSmall(let m):         return L("status.path_too_small", m)
        case .cancelled:                   return L("status.cancelled")
        case .done(let h, let m):          return L("status.done", h, m)
        case .noAnswer:                    return L("status.no_answer")
        }
    }

    private func errorText(_ e: ProbeError) -> String {
        switch e {
        case .emptyHost:                       return L("error.empty_host")
        case .boundUnreachable(let h, let i):  return L("error.bound_unreachable", h, i)
        case .resolve(let h):                  return L("error.resolve", h)
        case .icmpBlocked(let h):              return L("error.icmp_blocked", h)
        }
    }

    private func logNote(_ o: PingOutcome) -> String {
        switch o {
        case .ok:      return L("log.ok")
        case .tooLong: return L("log.toolong")
        case .noReply: return L("log.noreply")
        case .error:   return L("log.error")
        }
    }

    private func interfaceLabel(_ i: InterfaceInfo) -> String {
        let base = "\(i.name) · MTU \(i.mtu)"
        return i.isTunnel ? "\(base) · \(L("iface.tunnel"))" : base
    }

    // MARK: interpretation

    private struct Verdict { let text: String; let color: Color; let icon: String }

    /// Overhead of the measured MTU against a 1500-byte Ethernet underlay + likely protocol.
    private func overheadText(_ mtu: Int) -> String {
        let oh = max(0, kEthernetMTU - mtu)
        return L("overhead.value", oh, protocolHint(oh))
    }

    private func protocolHint(_ overhead: Int) -> String {
        switch overhead {
        case 0:        return L("proto.none")
        case 1...12:   return L("proto.pppoe")
        case 13...28:  return L("proto.gre")
        case 29...48:  return L("proto.l2tp")
        case 49...64:  return L("proto.wg4")
        case 65...84:  return L("proto.wg6")
        case 85...140: return L("proto.ipsec")
        default:       return L("proto.unknown")
        }
    }

    private func recommendation(_ mtu: Int, _ mode: ConnectionMode) -> String {
        switch mode {
        case .vpn: return L("rec.vpn", mtu, mtu)
        default:   return L("rec.default", mtu)
        }
    }

    private func verdict(_ mtu: Int, _ mode: ConnectionMode) -> Verdict {
        let green = "checkmark.seal.fill"
        let warn  = "exclamationmark.triangle.fill"
        let info  = "info.circle.fill"
        let bad   = "exclamationmark.octagon.fill"

        func v(_ key: String, _ color: Color, _ icon: String) -> Verdict {
            Verdict(text: L(key), color: color, icon: icon)
        }

        switch mode {
        case .vpn:
            switch mtu {
            case 1492...:     return v("verdict.vpn.high", .jumpitGold, info)
            case 1380..<1492: return v("verdict.vpn.normal", .jumpitOK, green)
            case 1280..<1380: return v("verdict.vpn.conservative", .jumpitOK, green)
            default:          return v("verdict.vpn.verylow", .jumpitWarn, warn)
            }
        case .direct:
            switch mtu {
            case 1500...:     return v("verdict.ethernet", .jumpitOK, green)
            case 1492..<1500: return v("verdict.pppoe", .jumpitOK, green)
            case 1280..<1492: return v("verdict.direct.reduced", .jumpitWarn, warn)
            default:          return v("verdict.direct.verylow", .jumpitDown, bad)
            }
        case .auto:
            switch mtu {
            case 1500...:     return v("verdict.ethernet", .jumpitOK, green)
            case 1492..<1500: return v("verdict.pppoe", .jumpitOK, green)
            case 1400..<1492: return v("verdict.auto.reduced", .jumpitGold, warn)
            case 1280..<1400: return v("verdict.auto.low", .jumpitWarn, warn)
            default:          return v("verdict.auto.verylow", .jumpitDown, bad)
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
