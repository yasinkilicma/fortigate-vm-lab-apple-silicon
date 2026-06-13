#!/usr/bin/env bash
# Client (Debian ARM64 cloud image) in eigenständigem QEMU, hinter der FortiGate.
# Voraussetzung: FortiGate (UTM) läuft und lauscht auf 127.0.0.1:4700 (socket-listen NIC = port3).
# Passe die Pfade an (LAB-Verzeichnis).
LAB="$HOME/kali-lab"
EDK2="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"   # Homebrew-QEMU edk2 (bedient serielle Konsole)
exec qemu-system-aarch64 \
  -name kali-client -machine virt -accel hvf -cpu host -smp 4 -m 3072 \
  -drive if=pflash,format=raw,readonly=on,file="$EDK2" \
  -drive if=pflash,format=raw,file="$LAB/edk2-vars.fd" \
  -drive if=virtio,format=qcow2,file="$LAB/debian-arm64.qcow2" \
  -drive if=virtio,format=raw,readonly=on,file="$LAB/seed.iso" \
  -netdev socket,id=net0,connect=127.0.0.1:4700 \
  -device virtio-net-pci,netdev=net0 \
  -serial tcp:127.0.0.1:4600,server -display none
