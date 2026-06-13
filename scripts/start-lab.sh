#!/bin/bash
# FortiGate-NSE4 lab başlatıcı: FortiGate (UTM) + Kali-client (qemu) socket-link ile
FUUID=E6133DD1-0297-4B83-9999-72BB1633FAB1
echo "[1/3] FortiGate (UTM) başlatılıyor..."
utmctl start "$FUUID" 2>/dev/null
echo "[2/3] FortiGate'in socket NIC'i (127.0.0.1:4700) dinlemesi bekleniyor..."
for i in $(seq 1 60); do lsof -nP -iTCP:4700 2>/dev/null | grep -q LISTEN && break; sleep 2; done
lsof -nP -iTCP:4700 2>/dev/null | grep -q LISTEN && echo "  -> 4700 dinliyor" || { echo "  -> FortiGate 4700 dinlemedi, çıkılıyor"; exit 1; }
echo "[3/3] Kali-client başlatılıyor..."
pkill -f debian-arm64.qcow2 2>/dev/null; sleep 1
nohup ~/kali-lab/run-cloud.sh > ~/kali-lab/qemu-client.log 2>&1 &
echo "  -> client pid $!"
echo ""
echo "ERİŞİM:"
echo "  FortiGate GUI : https://192.168.64.2  (admin / <admin-passwort>)"
echo "  FortiGate CLI : nc 127.0.0.1 4555"
echo "  Kali client   : nc 127.0.0.1 4600     (kali / kali)  IP 192.168.1.50"
