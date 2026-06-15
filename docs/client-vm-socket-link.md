# Client hinter die FortiGate hängen — QEMU Socket-Networking

Ziel: einen Linux-Client so ins Lab einbinden, dass sein **gesamter Datenverkehr durch die FortiGate**
geroutet/ge-NAT-et/inspiziert wird (Basis für IPS-, AV-, Web-Filter-Tests).

## Warum kein Kali-Installer

Der ARM64-Installer scheiterte in dieser Umgebung an jeder Ebene:

| Ebene | Problem |
|------|---------|
| Display | Installer-Kernel-Framebuffer rendert nie (hvf **und** TCG) — nur GRUB sichtbar |
| Serielle GRUB | UTMs edk2 gibt seriell aus, nimmt aber keine GRUB-Eingabe an |
| `-kernel`-Boot | keine UEFI-Umgebung → `grub-installer` setzt auf ARM64 keinen Bootloader |
| macOS-Host | kann ext4 nicht mounten → Kernel/Initrd nicht aus dem Image extrahierbar |

**Pivot:** direkt bootbares **Debian-12-ARM64-Cloud-Image** + cloud-init. *Kali = Debian + Tools* → die
Security-Tools per `apt` nachinstallieren.

## 1. Cloud-Image + Seed

```bash
# Debian ARM64 genericcloud qcow2
curl -L -o debian-arm64.qcow2 \
  https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.qcow2
qemu-img resize debian-arm64.qcow2 +13G

# NoCloud-Seed (siehe client/cloud-init/) -> ISO mit Label 'cidata'
hdiutil makehybrid -iso -joliet -default-volume-name cidata -o seed.iso seed/
```

## 2. Warum eigenständiges QEMU (nicht UTM)

- UTM **splittet** zusätzliche QEMU-Argumente an Leerzeichen → mehrwortiges `-append` / `-kernel`-Pfad unmöglich.
- UTM-**Sandbox** blockiert Dateizugriff für eigene `-kernel`-Pfade; UTMs edk2 bedient die serielle Konsole nicht.
- Homebrews QEMU (`brew install qemu`) + dessen `edk2-aarch64-code.fd` lösen beides.

Client-Start: [`../client/run-client-qemu.sh`](../client/run-client-qemu.sh)

## 3. Socket-Networking (das Bindeglied)

UTMs „Emulated" = QEMU `user`/SLIRP → pro VM isoliert, verbindet **keine** zwei VMs.
Lösung: QEMU **socket netdev** (eine Seite `listen`, andere `connect`) = echtes isoliertes L2.

**FortiGate (UTM)** bekommt eine socket-listen-NIC via `config.plist` → `:QEMU:AdditionalArguments`
(Tokens ohne Leerzeichen, überleben UTMs Split; TCP-Socket ≠ Dateizugriff, Sandbox erlaubt ihn):

```
-netdev  socket,id=lan,listen=127.0.0.1:4700
-device  virtio-net-pci,netdev=lan,mac=BC:24:11:5A:11:01
```

→ erscheint als **port3**. **Client** verbindet sich: `-netdev socket,id=net0,connect=127.0.0.1:4700`.

> **Reihenfolge:** FortiGate (UTM) zuerst starten (lauscht auf :4700), dann Client-QEMU.

## 4. FortiGate-Seite: port3 = LAN

```
config system interface
  edit port3
    set mode static
    set ip 192.0.2.99 255.255.255.0     # erst alte IP von port2 entfernen (sonst: Subnets overlap)
    set allowaccess ping https ssh
  next
end
config system dhcp server
  edit 1
    set interface port3                    # DHCP + Policy srcintf auf port3 umstellen
  next
end
```

Client: statische IP via netplan ([`../client/netplan-99-fgt-lan.yaml`](../client/netplan-99-fgt-lan.yaml)),
Gateway = FortiGate port3 (`192.0.2.99`).

## 5. Verifikation

```bash
ping -c3 192.0.2.99        # FortiGate          -> 0% loss
ping -c3 8.8.8.8             # Internet via NAT    -> 0% loss (inspiziert!)
nslookup google.com 8.8.8.8  # DNS durch die FW    -> aufgelöst
nmap -sn 192.0.2.99        # Host is up
```

## Lab starten

```bash
./scripts/start-lab.sh   # FortiGate (UTM) -> auf :4700 warten -> Client-QEMU
```

Zugriff: Client seriell `nc 127.0.0.1 4600` (kali / `<lab-passwort>`), FortiGate CLI `nc 127.0.0.1 4555`,
FortiGate GUI `https://198.51.100.2`.
