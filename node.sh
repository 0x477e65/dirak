#!/usr/bin/env bash
# ==============================================================
# Quantus Node Autostart & Watchdog (DIRAC)
# Uruchamia node w tmux z automatycznym restartem i logowaniem.
# Rewards address pobiera z /root/keys-dirac.txt.
# ==============================================================

unset TMUX
set -euo pipefail

# ---------------- CONFIG ----------------
NODENAME="Wlasna-Nazwa"
CHAIN_SPEC="/root/chain/dirac.raw.json"
BASE_PATH="/var/lib/quantus"
LOG_FILE="$BASE_PATH/node.log"
KEYS_FILE="/root/keys-dirac.txt"       # ✅ zmiana z seed.txt
EXTERNAL_MINER_URL="http://127.0.0.1:9833"
# -----------------------------------------

mkdir -p "$BASE_PATH"
touch "$LOG_FILE"

# ===== Pobranie rewards-address =====
if [[ ! -s "$KEYS_FILE" ]]; then
  echo "❌ Brak pliku $KEYS_FILE" >&2
  exit 1
fi

REWARDS_ADDR=$(grep -m1 -E "^ *Address:" "$KEYS_FILE" | sed -E 's/^ *Address:[[:space:]]*//; s/[[:space:]]//g')

if [[ -z "$REWARDS_ADDR" ]]; then
  echo "❌ Nie znaleziono Address w $KEYS_FILE" >&2
  exit 1
fi

# Zabicie starej sesji (jeśli istnieje)
tmux kill-session -t quantus-node 2>/dev/null || true

# ===== Komenda startowa =====
NODE_CMD=$(cat <<EOF
echo "[\$(date -Is)] ▶️ Start quantus-node (name: $NODENAME)" | tee -a $LOG_FILE
/usr/local/bin/quantus-node \
  --validator \
  --chain "$CHAIN_SPEC" \
  --base-path "$BASE_PATH" \
  --name "$NODENAME" \
  --rewards-address "$REWARDS_ADDR" \
  --rpc-methods=Safe \
  --rpc-cors=none \
  --pruning=1000 \
  --out-peers 50 \
  --in-peers 100 \
  --allow-private-ip \
  --external-miner-url "$EXTERNAL_MINER_URL" \
  2>&1 | tee -a "$LOG_FILE"
code=\${PIPESTATUS[0]}
echo "[\$(date -Is)] ⛔ quantus-node exited (code=\$code) — restart za 5s..." | tee -a "$LOG_FILE"
sleep 5
EOF

)

# ===== Uruchomienie w tmux z autorestartem =====
tmux new-session -d -s quantus-node "bash -lc '
  while true; do
    $NODE_CMD
  done
'"

# ===== Informacje końcowe =====
echo "✅ quantus-node (Dirac) uruchomiony w tmux (session: quantus-node)"
echo "🏦 Rewards address: $REWARDS_ADDR"
echo "📄 Log: $LOG_FILE"
echo "ℹ️  Podgląd: tmux attach -t quantus-node  (Ctrl+B, D aby wyjść)"
