# FortiGate-VM Lab auf Apple Silicon (Mac mini M4 + UTM)

Eine **native ARM64 FortiGate-VM 7.4.12** auf einem Mac mini M4 in [UTM](https://mac.getutm.app/) —
mit voller Hardware-Beschleunigung über Apples Hypervisor.framework statt langsamer x86-Emulation.
Aufgesetzt als Edge-Firewall-Heimlabor für die **NSE4**-Vorbereitung.

Diese Anleitung dokumentiert vor allem die **Stolpersteine, die kein Tutorial erwähnt**:

- 🧱 UTM lädt keine handgebauten `.utm`-Bundles
- 🔌 Die FortiOS-Konsole liegt seriell — Zugriff über **TCP** statt `utmctl attach` (das in 4.7.5 fehlt)
- 🖥️ Eine **unlizenzierte** FortiOS 7.4 sperrt die komplette Web-GUI
- ⚙️ `config.plist`-Änderungen greifen erst nach einem **Neustart der UTM-App**

> 📝 Ausführlicher Blogbeitrag (Deutsch): siehe Portfolio-Blog.

---

## Überblick

| | |
|---|---|
| **Host** | Mac mini M4, macOS, 16 GB RAM |
| **Hypervisor** | UTM 4.7.5 (QEMU-Backend + Apple `hvf`) |
| **Gast** | FortiGate-VM 7.4.12 ARM64 KVM, 1 vCPU / 2 GB |
| **Beschleunigung** | nativ (ARM64-auf-ARM64), keine Emulation |
| **Boot-Zeit** | ~55 s bis Login-Prompt |

## Topologie

```
Mac mini M4  (Host, 192.168.64.1)
    │
    └─ UTM 4.7.5  (QEMU + hvf)
         │
         └─ FortiGate-VM 7.4.12 ARM64  (1 vCPU / 2 GB)
              │
              ├─ port1  Shared/NAT  192.168.64.2     → WAN + Mgmt + Internet
              │           GUI: https://192.168.64.2
              │
              └─ port2  LAN          192.168.1.99/24
                          DHCP: .100–.200
                          Policy: LAN → WAN (NAT enable)
```

---

## Voraussetzungen

- Apple-Silicon-Mac mit [UTM](https://mac.getutm.app/) (`brew install --cask utm`)
- Fortinet-Support-Konto (kostenlos) für den Image-Download
- Das **native ARM64-KVM-Image**: im [Fortinet Support](https://support.fortinet.com/Download/VMImages.aspx)
  → Produkt **FortiGate** → Plattform **KVM** → Variante **„New deployment … ARM64"**
  (`FGT_ARM64_KVM-v7.4.x...out.kvm.zip`). Aus dem ZIP wird `fortios.qcow2` benötigt.

> ⚠️ Nicht die „Upgrade"-Datei und nicht **FortiFirewall (FFW)** nehmen.

---

## Schritt für Schritt

### 1. VM über den UTM-Wizard anlegen

UTM lädt extern erzeugte Bundles **nicht** (`Failed to create object`). Daher die VM einmal über den
Wizard anlegen:

- **Emulate** (nicht Virtualize — wir brauchen das QEMU-Backend) → **ARM64 (aarch64)**
- Betriebssystem **„Andere / Other"**
- Boot-Device **„Drive Image"** → die heruntergeladene `fortios.qcow2` importieren, **UEFI Boot** aktiviert lassen
- RAM **2048 MB**, Name z. B. `FortiGate-NSE4`

### 2. config.plist anpassen

Der Wizard erzeugt eine bewusst konservative Config. Mit `PlistBuddy` nachrüsten — siehe
[`utm/config-snippets.md`](utm/config-snippets.md):

```bash
PB=/usr/libexec/PlistBuddy
CFG="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/FortiGate-NSE4.utm/config.plist"

# Native ARM64-Beschleunigung
$PB -c "Set :System:CPU host"        "$CFG"
$PB -c "Set :QEMU:Hypervisor true"   "$CFG"
$PB -c "Set :System:CPUCount 1"      "$CFG"   # passend zum Eval-Lizenz-Limit

# Zweite NIC -> internes LAN (UTM-Mode 'Emulated')
$PB -c "Add :Network:1:Hardware string virtio-net-pci" "$CFG"
$PB -c "Add :Network:1:Mode string Emulated"           "$CFG"
$PB -c "Add :Network:1:IsolateFromHost bool false"     "$CFG"
$PB -c "Add :Network:1:PortForward array"              "$CFG"

# Serielle Konsole als TCP-Server (fuer CLI-Zugriff/Automatisierung)
$PB -c "Add :Serial:0:Mode string TcpServer"   "$CFG"
$PB -c "Add :Serial:0:Target string Auto"      "$CFG"
$PB -c "Add :Serial:0:TcpPort integer 4555"    "$CFG"
$PB -c "Add :Serial:0:WaitForConnection bool false" "$CFG"
```

> **Wichtig:** Nach jeder Änderung die UTM-**App** neu starten, sonst nutzt `utmctl start` die alte
> In-Memory-Config: `pkill -9 -f UTM.app && open -a UTM`

### 3. Starten & serielle Konsole

```bash
UUID=$(utmctl list | awk '/FortiGate/{print $1}')
utmctl start "$UUID"
# ~55 s warten, dann verbinden:
nc 127.0.0.1 4555
```

Das Grafik-Display zeigt nur „Display output is not active" — FortiOS spricht auf ARM64-KVM seriell.
Login: `admin` / leeres Passwort, danach **erzwungener Passwortwechsel**.
Automatisiert: [`scripts/fg-login.exp`](scripts/fg-login.exp).

### 4. FortiGate-Grundkonfiguration

Komplette Baseline (Interfaces, DHCP-Server, LAN→WAN-Policy) in
[`configs/fortigate-baseline.conf`](configs/fortigate-baseline.conf). Erster Befehl immer:

```
config system console
  set output standard      # verhindert --More--, wichtig fuer Skripte
end
```

### 5. Lizenz aktivieren (sonst keine GUI)

Eine FortiGate-VM mit `License Status: Invalid` sperrt die Web-GUI komplett auf die Lizenzseite.
Im GUI unter **System → FortiGate VM License → Evaluation license** mit dem FortiCare-Konto aktivieren.

> Die kostenlose Eval-Lizenz ist **einmalig pro FortiCare-Konto** und limitiert auf
> **1 vCPU, 2 GB, max. 3 Interfaces / 3 Policies / 3 Routen**.

Danach auf **1 vCPU** bleiben (`CPUCount 1` + UTM-App-Neustart), sonst Warnung
„exceeding allowed 1 CPUs".

---

## Verifikation

```bash
# FortiGate -> Internet (durch die Mac-NAT)
execute ping 8.8.8.8        # → 0% loss, ~10 ms

# Mac -> FortiGate-GUI
curl -k -o /dev/null -w "%{http_code}\n" https://192.168.64.2   # → 200
```

Routing-Tabelle:

```
S*  0.0.0.0/0 [5/0] via 192.168.64.1, port1
C   192.168.1.0/24 is directly connected, port2
C   192.168.64.0/24 is directly connected, port1
```

---

## Stolpersteine (Gotchas)

| # | Problem | Lösung |
|---|---------|--------|
| 1 | UTM lädt handgebautes Bundle nicht (`Failed to create object`) | VM über den Wizard anlegen, dann `config.plist` editieren |
| 2 | `config.plist`-Änderung wirkt nicht | UTM-**App** neu starten (nicht nur die VM) |
| 3 | VM wird „nicht verfügbar" nach Serial-Edit | Serial-Mode heißt `Terminal`, nicht `Builtin`; Schema notfalls per GUI ermitteln |
| 4 | Display bleibt schwarz | FortiOS-Konsole liegt seriell → TCP-Serielle nutzen |
| 5 | `utmctl attach` tut nichts | In UTM 4.7.5 nicht implementiert → `nc`/`expect` auf TCP-Port |
| 6 | Web-GUI gesperrt | unlizenziert → kostenlose Evaluation-Lizenz aktivieren |
| 7 | „exceeding allowed 1 CPUs" trotz `CPUCount 1` | UTM ignoriert es bis App-Neustart; danach `-smp 1` |

---

## Repo-Struktur

```
.
├── README.md
├── configs/
│   └── fortigate-baseline.conf     # FortiOS-CLI-Baseline (Interfaces, DHCP, Policy)
├── client/                         # Client hinter der Firewall (Debian-Cloud + Socket-Net)
│   ├── cloud-init/{user-data,meta-data}
│   ├── netplan-99-fgt-lan.yaml     # statische LAN-IP hinter der FortiGate
│   └── run-client-qemu.sh          # Client-QEMU, socket-connect zur FortiGate
├── docs/
│   └── client-vm-socket-link.md    # Client hinter die FortiGate hängen (QEMU socket netdev)
├── scripts/
│   ├── start-lab.sh                # ganzes Lab starten (FortiGate + Client)
│   ├── fg-serial-console.sh        # mit der seriellen Konsole verbinden (nc)
│   └── fg-login.exp                # automatischer Login + Passwortwechsel (expect)
└── utm/
    └── config-snippets.md          # config.plist-Anpassungen & UTM-Notizen
```

## Client hinter der Firewall

Ein Linux-Client wird über **QEMU socket-networking** hinter die FortiGate gehängt, sodass sein gesamter
Verkehr inspiziert wird. Da der Kali-Installer in dieser Umgebung an jeder Ebene scheitert, kommt ein
direkt bootbares **Debian-ARM64-Cloud-Image** (cloud-init) zum Einsatz — *Kali = Debian + Tools*.
Vollständige Anleitung: [`docs/client-vm-socket-link.md`](docs/client-vm-socket-link.md).

---

## Hinweise

- **Bildungs-/Laborzweck.** FortiGate, FortiOS und NSE sind Marken von Fortinet, Inc.
  Dieses Repo enthält keine Fortinet-Software, nur eigene Konfiguration und Anleitung.
- Platzhalter wie `<starkes-Passwort>` durch eigene Werte ersetzen. Keine echten Zugangsdaten
  committen.

## Lizenz

MIT — siehe [`LICENSE`](LICENSE).
