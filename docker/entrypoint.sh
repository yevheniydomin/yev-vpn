#!/bin/bash
set -e

DATA_DIR="/data"
CONFIGS_DIR="$DATA_DIR/client-configs"
SECRETS="$DATA_DIR/secrets.json"

# ─── Defaults (override via env vars or .env) ───────────────────────────────
XRAY_PORT="${XRAY_PORT:-443}"
XRAY_SNI="${XRAY_SNI:-www.microsoft.com}"
AWG_PORT="${AWG_PORT:-8443}"
AWG_SUBNET="${AWG_SUBNET:-10.10.10.0/24}"
CLIENT_COUNT="${CLIENT_COUNT:-5}"
DNS="${DNS:-1.1.1.1,8.8.8.8}"

# ─── Subcommand: print client configs ───────────────────────────────────────
if [ "${1}" = "configs" ]; then
  if [ ! -d "$CONFIGS_DIR" ]; then
    echo "No configs yet. Start the VPN first." >&2
    exit 1
  fi
  echo "=== VLESS Link (copy to v2rayNG / Nekoray / Hiddify) ==="
  cat "$CONFIGS_DIR/vless-link.txt"
  echo ""
  if [ -f "$CONFIGS_DIR/vless-qr.txt" ]; then
    echo "=== VLESS QR ==="
    cat "$CONFIGS_DIR/vless-qr.txt"
    echo ""
  fi
  echo "=== AmneziaWG Client Configs ==="
  for f in "$CONFIGS_DIR"/awg-client-*.conf; do
    [ -f "$f" ] || continue
    echo "--- $(basename "$f") ---"
    cat "$f"
    echo ""
  done
  exit 0
fi

# ─── Network detection ──────────────────────────────────────────────────────
PRIMARY_IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
SERVER_IP="${SERVER_IP:-$(curl -s --retry 5 --retry-delay 2 ifconfig.me)}"
SUBNET_BASE=$(echo "$AWG_SUBNET" | cut -d'.' -f1-3)

echo "=== Family VPN starting ==="
echo "Server IP: $SERVER_IP | Interface: $PRIMARY_IFACE"

# ─── Kernel params + NAT ────────────────────────────────────────────────────
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

iptables -t nat -C POSTROUTING -o "$PRIMARY_IFACE" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$PRIMARY_IFACE" -j MASQUERADE
iptables -C FORWARD -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -j ACCEPT

# ─── Generate secrets (first run only) ──────────────────────────────────────
generate_secrets() {
  if [ -f "$SECRETS" ]; then return; fi
  echo "Generating VPN keys (first run)..."

  # XRay keys
  XRAY_KEYS=$(/usr/local/bin/xray x25519)
  XRAY_PRIV=$(echo "$XRAY_KEYS" | grep "PrivateKey:" | awk '{print $2}')
  XRAY_PUB=$(echo "$XRAY_KEYS" | grep "Password:" | awk '{print $2}')
  XRAY_UUID=$(/usr/local/bin/xray uuid)
  XRAY_SID=$(openssl rand -hex 4)

  # AmneziaWG server keys
  AWG_PRIV=$(awg genkey)
  AWG_PUB=$(echo "$AWG_PRIV" | awg pubkey)

  # Random obfuscation params (unique per deployment)
  Jc=$((RANDOM % 10 + 3))
  Jmin=$((RANDOM % 50 + 40))
  Jmax=$((RANDOM % 500 + 500))
  S1=$((RANDOM % 50 + 100))
  S2=$((RANDOM % 30 + 50))
  H1=$((RANDOM % 2147483647))
  H2=$((RANDOM % 2147483647))
  H3=$((RANDOM % 2147483647))
  H4=$((RANDOM % 2147483647))

  # Client keys
  CLIENTS="[]"
  for i in $(seq 1 "$CLIENT_COUNT"); do
    CPRIV=$(awg genkey)
    CPUB=$(echo "$CPRIV" | awg pubkey)
    CPSK=$(awg genpsk)
    CIP="$SUBNET_BASE.$((i + 1))"
    CLIENTS=$(echo "$CLIENTS" | jq \
      --arg priv "$CPRIV" --arg pub "$CPUB" --arg psk "$CPSK" --arg ip "$CIP" \
      '. + [{"private_key": $priv, "public_key": $pub, "psk": $psk, "ip": $ip}]')
  done

  jq -n \
    --arg xpriv "$XRAY_PRIV" --arg xpub "$XRAY_PUB" \
    --arg xuuid "$XRAY_UUID" --arg xsid "$XRAY_SID" \
    --arg apriv "$AWG_PRIV" --arg apub "$AWG_PUB" \
    --argjson jc "$Jc" --argjson jmin "$Jmin" --argjson jmax "$Jmax" \
    --argjson s1 "$S1" --argjson s2 "$S2" \
    --argjson h1 "$H1" --argjson h2 "$H2" --argjson h3 "$H3" --argjson h4 "$H4" \
    --argjson clients "$CLIENTS" \
    '{
      xray: { private_key: $xpriv, public_key: $xpub, uuid: $xuuid, short_id: $xsid },
      awg:  { server_private_key: $apriv, server_public_key: $apub,
              jc: $jc, jmin: $jmin, jmax: $jmax, s1: $s1, s2: $s2,
              h1: $h1, h2: $h2, h3: $h3, h4: $h4,
              clients: $clients }
    }' > "$SECRETS"

  chmod 600 "$SECRETS"
  echo "Keys saved to $SECRETS"
}

# ─── Generate configs (every start — picks up new SERVER_IP) ────────────────
generate_configs() {
  mkdir -p "$CONFIGS_DIR"

  # Read XRay secrets
  XRAY_PRIV=$(jq -r '.xray.private_key' "$SECRETS")
  XRAY_PUB=$(jq -r '.xray.public_key' "$SECRETS")
  XRAY_UUID=$(jq -r '.xray.uuid' "$SECRETS")
  XRAY_SID=$(jq -r '.xray.short_id' "$SECRETS")

  # ── XRay server config ──
  cat > "$DATA_DIR/xray-config.json" <<EOF
{
  "log": { "loglevel": "warning", "access": "none", "error": "/var/log/xray/error.log" },
  "inbounds": [{
    "port": $XRAY_PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$XRAY_UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$XRAY_SNI:443",
        "xver": 0,
        "serverNames": ["$XRAY_SNI"],
        "privateKey": "$XRAY_PRIV",
        "shortIds": ["$XRAY_SID", ""]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": { "rules": [{ "type": "field", "outboundTag": "block", "protocol": ["bittorrent"] }] }
}
EOF
  mkdir -p /var/log/xray

  # ── VLESS client link ──
  VLESS_LINK="vless://$XRAY_UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$XRAY_SNI&fp=chrome&pbk=$XRAY_PUB&sid=$XRAY_SID&type=tcp#Family-VPN"
  echo "$VLESS_LINK" > "$CONFIGS_DIR/vless-link.txt"
  qrencode -t UTF8 "$VLESS_LINK" > "$CONFIGS_DIR/vless-qr.txt" 2>/dev/null || true

  # Read AmneziaWG secrets
  AWG_PRIV=$(jq -r '.awg.server_private_key' "$SECRETS")
  AWG_PUB=$(jq -r '.awg.server_public_key' "$SECRETS")
  Jc=$(jq -r '.awg.jc' "$SECRETS")
  Jmin=$(jq -r '.awg.jmin' "$SECRETS")
  Jmax=$(jq -r '.awg.jmax' "$SECRETS")
  S1=$(jq -r '.awg.s1' "$SECRETS")
  S2=$(jq -r '.awg.s2' "$SECRETS")
  H1=$(jq -r '.awg.h1' "$SECRETS")
  H2=$(jq -r '.awg.h2' "$SECRETS")
  H3=$(jq -r '.awg.h3' "$SECRETS")
  H4=$(jq -r '.awg.h4' "$SECRETS")

  # ── AmneziaWG server config ──
  cat > "$DATA_DIR/awg0.conf" <<EOF
[Interface]
PrivateKey = $AWG_PRIV
Address = $SUBNET_BASE.1/24
ListenPort = $AWG_PORT
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

EOF

  # ── AmneziaWG peers + client configs ──
  NUM_CLIENTS=$(jq '.awg.clients | length' "$SECRETS")
  for i in $(seq 0 $((NUM_CLIENTS - 1))); do
    CPRIV=$(jq -r ".awg.clients[$i].private_key" "$SECRETS")
    CPUB=$(jq -r ".awg.clients[$i].public_key" "$SECRETS")
    CPSK=$(jq -r ".awg.clients[$i].psk" "$SECRETS")
    CIP=$(jq -r ".awg.clients[$i].ip" "$SECRETS")

    # Append peer to server config
    cat >> "$DATA_DIR/awg0.conf" <<EOF
[Peer]
PublicKey = $CPUB
PresharedKey = $CPSK
AllowedIPs = $CIP/32

EOF

    # Write client config
    CLIENT_NUM=$((i + 1))
    cat > "$CONFIGS_DIR/awg-client-$CLIENT_NUM.conf" <<EOF
[Interface]
PrivateKey = $CPRIV
Address = $CIP/32
DNS = $DNS
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
PublicKey = $AWG_PUB
PresharedKey = $CPSK
Endpoint = $SERVER_IP:$AWG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    qrencode -t UTF8 < "$CONFIGS_DIR/awg-client-$CLIENT_NUM.conf" \
      > "$CONFIGS_DIR/awg-client-$CLIENT_NUM-qr.txt" 2>/dev/null || true
  done

  chmod 600 "$DATA_DIR/awg0.conf" "$CONFIGS_DIR"/*.conf
}

# ─── Cleanup on shutdown ────────────────────────────────────────────────────
cleanup() {
  echo "Shutting down..."
  WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go awg-quick down "$DATA_DIR/awg0.conf" 2>/dev/null || true
  kill "$XRAY_PID" 2>/dev/null || true
  wait "$XRAY_PID" 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

# ─── Main ────────────────────────────────────────────────────────────────────
generate_secrets
generate_configs

# Start XRay (background)
/usr/local/bin/xray run -c "$DATA_DIR/xray-config.json" &
XRAY_PID=$!

# Start AmneziaWG (creates awg0 interface, amneziawg-go stays in background)
export WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go
awg-quick up "$DATA_DIR/awg0.conf" || echo "WARNING: AmneziaWG failed to start"

echo ""
echo "=== VPN is running ==="
echo "  VLESS+Reality : port $XRAY_PORT/tcp"
echo "  AmneziaWG     : port $AWG_PORT/udp"
echo "  Clients       : $CLIENT_COUNT"
echo ""
echo "Get client configs:"
echo "  docker compose exec vpn /entrypoint.sh configs"
echo ""

# Keep container alive — wait for XRay
wait "$XRAY_PID"
