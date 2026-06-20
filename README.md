# JumpIT MTU Finder

Native SwiftUI-App für macOS (JumpIT-Branding), die den optimalen MTU-Wert zu
einem Zielhost ermittelt — per Binary-Search über Don't-Fragment-Pings.

## Funktionsweise

Es wird das größte ICMP-Paket gesucht, das mit gesetztem **Don't-Fragment-Bit**
(`ping -D`) noch eine Antwort bekommt. Das größte nicht-fragmentierte Paket
definiert die Pfad-MTU:

```
MTU = ICMP-Payload + 28  (20 B IPv4-Header + 8 B ICMP-Header)
```

- **Exit 0** → Paket passt
- **„Message too long"** → überschreitet die lokale Interface-MTU (harter Abbruch)
- **keine Antwort** → Pfad-MTU zu klein (ICMP „fragmentation needed") oder Verlust
  → wird bis zu 2× wiederholt, um Paketverlust auszuschließen

Eine Erreichbarkeitsprüfung mit kleinem Paket läuft vorab; antwortet der Host
gar nicht auf ICMP, wird das klar gemeldet statt „MTU nicht gefunden".

## Sprachen

Die App ist vollständig lokalisiert in **Deutsch, Englisch, Spanisch, Katalanisch,
Französisch und Italienisch**. Standardmäßig folgt sie der macOS-Systemsprache; über
das Globus-Menü oben rechts lässt sich die Sprache **live** umschalten (gemerkt über
`@AppStorage`). Alle Texte liegen in `localization/<lang>.lproj/Localizable.strings`;
die Engine (`MTUProber`) liefert sprachneutrale Zustände, die UI rendert sie über `L(...)`.

## Bauen

Benötigt nur die Command Line Tools (`swiftc` + macOS SDK), kein Xcode-Projekt:

```bash
./build.sh          # erzeugt "MTU Finder.app"
open "MTU Finder.app"
```

## Verbindungstyp

Über den Schalter **Verbindungstyp** wird gewählt, wie das Ergebnis bewertet wird
(die Messung selbst ist identisch — gemessen wird immer der reale Pfad):

- **Automatisch** — Bewertung nach typischen MTU-Bereichen.
- **Direkt (ohne VPN)** — erwartet 1500 (bzw. 1492 bei PPPoE/DSL); ein deutlich
  niedrigerer Wert wird als unerwarteter Tunnel/Drosselung markiert.
- **Über VPN** — eine reduzierte MTU ist hier *normal und gut* (grün). Zusätzlich
  werden **Tunnel-Overhead** (ggü. 1500) und das **wahrscheinliche Protokoll**
  angezeigt (z. B. 80 B → WireGuard über IPv6) und die Empfehlung passt sich an:
  `MTU = <wert>` für die WireGuard-Config bzw. `ifconfig <utunX> mtu <wert>`.

## Erweitert: Interface-Bindung

Unter **Erweitert** lässt sich ein festes Netzwerk-Interface wählen. Die Pings
werden dann via `ping -b <iface>` an dieses Interface gebunden (statt über das
Standard-Routing) — nützlich, um gezielt *durch einen Tunnel* (`utunX`) oder über
ein bestimmtes physisches Interface zu messen. Die obere Suchgrenze richtet sich
dabei nach der MTU des gebundenen Interfaces. Das Ziel muss über dieses Interface
erreichbar sein; andernfalls meldet die App das klar.

## Icon

Das App-Icon (`icon/AppIcon.svg` / via Higgsfield generiert in `icon/`) nutzt den
JumpIT-Verlauf Orange `#f19a3a` → Gold `#f4bf36`. Erzeugung der `.icns`:

```bash
cd icon && python3 make_icns.py higgsfield_icon.png icon_master_1024.png
# danach iconset -> iconutil -c icns (siehe build.sh kopiert AppIcon.icns ins Bundle)
```

## MTU-Interpretation

| Wert        | Bedeutung                                            |
|-------------|------------------------------------------------------|
| ≥ 1500      | Ethernet-Standard, voller Durchsatz                  |
| 1492–1499   | PPPoE/DSL typisch                                    |
| 1400–1491   | Tunnel/VPN (WireGuard, IPsec, PPPoE-Overhead)        |
| 1280–1399   | verschachtelte/konservative Tunnel                   |
| < 1280      | ungewöhnlich niedrig — Pfad prüfen                   |

## MTU setzen

```bash
networksetup -listallnetworkservices          # Dienstnamen anzeigen
sudo networksetup -setMTU "Wi-Fi" 1420         # Wert übernehmen
```

## Projektstruktur

- `Sources/MTUProber.swift`  — Mess-Engine (Ping, Binary-Search, State, Interface-Bindung)
- `Sources/NetworkInfo.swift` — Gateway + Interface-/MTU-Erkennung
- `Sources/ContentView.swift` — SwiftUI-Oberfläche + JumpIT-Branding
- `Sources/MTUFinderApp.swift` — App-Einstieg
- `icon/` — AppIcon.svg, Higgsfield-Render, make_icns.py, AppIcon.icns
- `Info.plist`, `build.sh`
