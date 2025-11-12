  GNU nano 6.2                                                                           miner-start.sh
#!/usr/bin/env bash
# ==============================================================
# Quantus Miner Autostart & Watchdog (DIRAk)
# Uruchamia minera w tmux z automatycznym restartem i logowaniem
# ==============================================================

BASE_PATH="/var/lib/quantus"
LOG_FILE="${BASE_PATH}/miner.log"
mkdir -p "$BASE_PATH"
touch "$LOG_FILE"

# Zabicie wszystkich sesji tmux zawierających "miner"
tmux ls 2>/dev/null | awk -F: '/miner/ {print $1}' | xargs -r -n1 tmux kill-session -t

# Start minera z autorestartem i logowaniem
tmux new-session -d -s quantus-miner "bash -lc '
  while true; do
    WORKERS=\$(nproc)
    echo \"[\$(date -Is)] ▶️ Start quantus-miner (\$WORKERS workers)\" | tee -a ${LOG_FILE}
    /usr/local/bin/quantus-miner --workers \$WORKERS 2>&1 | tee -a ${LOG_FILE}
    code=\${PIPESTATUS[0]}
    echo \"[\$(date -Is)] ⛔ quantus-miner exited (code=\$code) — restart za 5s...\" | tee -a ${LOG_FILE}
    sleep 5
  done
'"

echo "✅ quantus-miner (Dirac) uruchomiony w tmux (session: quantus-miner)"
echo "📄 Log: ${LOG_FILE}"
echo "ℹ️  Podgląd: tmux attach -t quantus-miner  (Ctrl+B, D aby wyjść)"
