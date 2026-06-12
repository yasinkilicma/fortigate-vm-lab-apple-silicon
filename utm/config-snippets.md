# UTM `config.plist` — Anpassungen & Notizen

Die VM wird **einmal über den UTM-Wizard** angelegt (siehe README, Schritt 1). Danach liegt die
Konfiguration unter:

```
~/Library/Containers/com.utmapp.UTM/Data/Documents/<NAME>.utm/config.plist
```

Editiert wird mit Apples `PlistBuddy` (`/usr/libexec/PlistBuddy`). **Nach jeder Änderung die UTM-App
neu starten** (`pkill -9 -f UTM.app && open -a UTM`), sonst greift die Änderung nicht.

## Relevante Schlüssel

| Pfad | Wert | Zweck |
|------|------|-------|
| `:System:Architecture` | `aarch64` | ARM64-Gast |
| `:System:Target` | `virt` | QEMU `virt`-Maschine |
| `:System:CPU` | `host` | nötig für `hvf` |
| `:System:CPUCount` | `1` | Eval-Lizenz-Limit (1 vCPU) |
| `:QEMU:Hypervisor` | `true` | Apple Hypervisor.framework (native Beschleunigung) |
| `:QEMU:UEFIBoot` | `true` | ARM64-KVM-Image bootet über UEFI |
| `:Drive:0:Interface` | `VirtIO` | Boot-Disk (`fortios.qcow2`) |

## Netzwerk-Interfaces

UTM bildet die Netzwerk-Modi so auf QEMU ab:

| UTM-Mode | QEMU-Netdev | Verhalten |
|----------|-------------|-----------|
| `Shared`   | `vmnet-shared` | NAT, geteilt mit Host (hier 192.168.64.0/24) — **port1/WAN** |
| `Emulated` | `user` (SLIRP)  | per-VM-NAT, **isoliert** — verbindet KEINE zwei VMs |
| `Host`     | `vmnet-host`    | Host-only, eigenes DHCP von macOS |
| `Bridged`  | `vmnet-bridged` | an physische NIC gebrückt |

```bash
# port2 als zweites Interface (UTM-Mode 'Emulated')
$PB -c "Add :Network:1:Hardware string virtio-net-pci" "$CFG"
$PB -c "Add :Network:1:Mode string Emulated"           "$CFG"
$PB -c "Add :Network:1:IsolateFromHost bool false"     "$CFG"
$PB -c "Add :Network:1:PortForward array"              "$CFG"
```

> **Hinweis zur Client-VM:** `Emulated` (= QEMU `user`/SLIRP) verbindet keine zwei VMs miteinander.
> Um eine Client-VM *hinter* die FortiGate zu hängen (Traffic-Inspektion), braucht es ein echtes
> isoliertes L2-Segment — z. B. über QEMU-Socket-Networking (`-netdev socket,listen/connect`) via
> `AdditionalArguments` auf beiden VMs. (In diesem Lab der nächste Ausbauschritt.)

## Serielle Konsole

FortiOS gibt auf ARM64-KVM nichts auf dem Grafik-Display aus — die Konsole liegt seriell.
`utmctl attach` ist in UTM 4.7.5 **nicht implementiert**, daher die Serielle als **TCP-Server**:

```bash
$PB -c "Add :Serial:0:Mode string TcpServer"        "$CFG"
$PB -c "Add :Serial:0:Target string Auto"           "$CFG"
$PB -c "Add :Serial:0:TcpPort integer 4555"         "$CFG"
$PB -c "Add :Serial:0:WaitForConnection bool false" "$CFG"
```

Verbindung: `nc 127.0.0.1 4555`.

> **Enum-Falle:** Der GUI-„Built-In Terminal"-Modus heißt in der Plist `Terminal` (nicht `Builtin`).
> Falsche Enum-Werte → UTM markiert die VM als „nicht verfügbar". Unsichere Schemata am besten
> ermitteln, indem man das Gerät einmal per UTM-GUI hinzufügt und die resultierende Plist ausliest.

## Verifikation der vCPU-Anzahl

```bash
ps -ww -o command= -p "$(pgrep -f '[q]emu' | head -1)" | grep -oE '\-smp [^ ]+'
# erwartet: -smp cpus=1,sockets=1,cores=1,threads=1
```
