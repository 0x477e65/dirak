#!/usr/bin/env bash
# Quantus: Migracja na testnet DIRAK (build node + miner + backup + klucze) 
# Ubuntu 22.04/24.04 (x86_64 lub ARM64). Uruchamiaj jako root.
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# 0) Flagi noda (dla Dirac)
# ────────────────────────────────────────────────────────────────
QUANTUS_NODE_FLAGS="\
  --base-path /var/lib/quantus \
  --name \"twojaNazwa\" \
  --rpc-methods=Safe \
  --rpc-cors=none \
  --pruning=1000 \
  --external-miner-url http://127.0.0.1:9833 \
"

# ────────────────────────────────────────────────────────────────
# 1) Konfiguracja ścieżek i repozytoriów
# ────────────────────────────────────────────────────────────────
CHAIN_NAME="dirac"
BASE_PATH="/var/lib/quantus"
CHAIN_DIR="/root/chain"
BACKUP_ROOT="/root/backup"
WORK="/opt/quantus-build"

NODE_BIN="/usr/local/bin/quantus-node"
MINER_BIN="/usr/local/bin/quantus-miner"

CHAIN_TAG="v0.4.2"
MINER_TAG="v1.0.0"

# Plik z danymi kluczy (konto + peer-id)
KEYS_FILE="/root/keys-dirac.txt"

# ────────────────────────────────────────────────────────────────
# 2) Przygotowanie systemu
# ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Uruchom jako root."; exit 1; }

TS="$(date -u +"%Y%m%d-%H%M%S")"
mkdir -p "$WORK" "$BASE_PATH" "$CHAIN_DIR" "$BACKUP_ROOT"
umask 077

say(){ echo -e "\e[1m$1\e[0m"; }

say "⏹️  Zatrzymuję stare instancje Quantus..."
systemctl stop quantus-node 2>/dev/null || true
systemctl stop quantus-miner 2>/dev/null || true
pkill -15 -x quantus-node 2>/dev/null || true
pkill -15 -x quantus-miner 2>/dev/null || true
sleep 1

say "⬆️  Aktualizuję system i instaluję zależności build..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  build-essential clang llvm libclang-dev pkg-config libssl-dev \
  git curl jq tmux cmake unzip zstd protobuf-compiler ca-certificates \
  lld rustc

# ────────────────────────────────────────────────────────────────
# 3) Backup starego testnetu i kluczy
# ────────────────────────────────────────────────────────────────
say "📦  Backup danych Schrödinger i kluczy..."
SCHR_DST="$BACKUP_ROOT/Schrodinger-$TS"
SAFE="$BACKUP_ROOT/node-keys-$TS"
mkdir -p "$SAFE"

if [ -d "$BASE_PATH/chains/schrodinger" ]; then
  mkdir -p "$SCHR_DST"
  mv "$BASE_PATH/chains/schrodinger" "$SCHR_DST/"
fi

for p in \
  "$BASE_PATH/network/secret_ed25519" \
  "$BASE_PATH/network/libp2p_secret" \
  "$BASE_PATH/node-key" \
  "/root/.local/share/quantus/network/secret_ed25519" \
  "/root/.local/share/quantus/network/libp2p_secret"
do
  [ -f "$p" ] && cp -a "$p" "$SAFE/"
done

# ────────────────────────────────────────────────────────────────
# 4) Instalacja Rust + wszystkie potrzebne targety
# ────────────────────────────────────────────────────────────────
say "🦀  Instaluję Rust nightly i wymagane targety..."
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# shellcheck disable=SC1090
source "$HOME/.cargo/env"

rustup toolchain install nightly >/dev/null 2>&1 || true
rustup default nightly >/dev/null 2>&1 || true
rustup component add rust-src llvm-tools-preview --toolchain nightly || true
rustup target add wasm32-unknown-unknown --toolchain nightly || true
rustup target add wasm32v1-none --toolchain nightly >/dev/null 2>&1 || true
rustup target add riscv64imac-unknown-none-elf --toolchain nightly || true
rustup target add riscv64imac-unknown-none-polkavm --toolchain nightly || true

export CARGO_NET_GIT_FETCH_WITH_CLI=true
export RUSTFLAGS="-C target-cpu=native"

# ────────────────────────────────────────────────────────────────
# 5) Budowa quantus-node (Dirac 0.4.x)
# ────────────────────────────────────────────────────────────────
say "🛠️  Buduję quantus-node (${CHAIN_TAG})..."
rm -rf "$WORK/chain"
git clone --depth=1 --branch "$CHAIN_TAG" https://github.com/Quantus-Network/chain.git "$WORK/chain"
cd "$WORK/chain"
rustup override set nightly >/dev/null 2>&1 || true
cargo +nightly build --locked --release -p quantus-node
install -m 0755 target/release/quantus-node "$NODE_BIN"

# ────────────────────────────────────────────────────────────────
# 6) Budowa quantus-miner (1.0.x)
# ────────────────────────────────────────────────────────────────
say "⚒️  Buduję quantus-miner (${MINER_TAG})..."
rm -rf "$WORK/quantus-miner"
git clone --depth=1 --branch "$MINER_TAG" https://github.com/Quantus-Network/quantus-miner.git "$WORK/quantus-miner"
cd "$WORK/quantus-miner"
rustup override set nightly >/dev/null 2>&1 || true
cargo +nightly build --locked --release
install -m 0755 target/release/quantus-miner "$MINER_BIN"

# ────────────────────────────────────────────────────────────────
# 7) Generacja spec Dirac
# ────────────────────────────────────────────────────────────────
say "📄  Generuję plik spec Dirac..."
mkdir -p "$CHAIN_DIR"
if "$NODE_BIN" build-spec --chain "$CHAIN_NAME" > "$CHAIN_DIR/$CHAIN_NAME.json" 2>/dev/null; then
  "$NODE_BIN" build-spec --chain "$CHAIN_DIR/$CHAIN_NAME.json" --raw > "$CHAIN_DIR/$CHAIN_NAME.raw.json"
else
  echo "Brak aliasu 'dirac' — użyjesz '--chain dirac' przy starcie." > "$CHAIN_DIR/dirac.warn.txt"
fi

# ────────────────────────────────────────────────────────────────
# 8) Tworzenie kluczy: konto (rewards) + sieciowy (peer-id)
# ────────────────────────────────────────────────────────────────
say "🔑  Tworzę klucz konta (rewards) i zapisuję do $KEYS_FILE..."
{
  echo "==================== Quantus DIRAC Keys ===================="
  echo "Timestamp (UTC): $TS"
  echo
  echo "---- [KONTO / REWARDS ADDRESS] ----"
} >> "$KEYS_FILE"

# 8a) Konto (HD/BIP-44): quantus-node key quantus
QU_OUT="$("$NODE_BIN" key quantus)"
echo "$QU_OUT" >> "$KEYS_FILE"
echo >> "$KEYS_FILE"

# Wyciągnij adres (Address: ... lub SS58 Address: ...)
REWARDS_ADDR="$(printf '%s\n' "$QU_OUT" | grep -E '^(SS58 Address|Address):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//')"

# 8b) Klucz sieciowy (peer-id): secret_dilithium
say "🌐  Tworzę klucz sieciowy (Peer ID) — bezpieczny plik w ${BASE_PATH}/chains/dirac/network/ ..."
mkdir -p "$BASE_PATH/chains/dirac/network"

PEER_FILE="$BASE_PATH/chains/dirac/network/secret_dilithium"
PEER_NOTE="(istniał wcześniej — nie nadpisano)"
PEER_ID=""

if [ -f "$PEER_FILE" ]; then
  # Plik istnieje — spróbuj pobrać Peer ID (niektóre buildy go drukują)
  PEER_ID="$("$NODE_BIN" key generate-node-key --file "$PEER_FILE" 2>&1 >/dev/null || true)"
else
  # Utwórz nowy klucz sieciowy
  PEER_ID="$("$NODE_BIN" key generate-node-key --file "$PEER_FILE" 2>&1 >/dev/null || true)"
  chmod 600 "$PEER_FILE"
  PEER_NOTE="(utworzono nowy)"
fi

{
  echo "---- [SIECIOWE / PEER-ID] (NIE UŻYWAĆ DO REWARDS ADDRESS) ----"
  echo "Peer key file: $PEER_FILE $PEER_NOTE"
  if [ -n "$PEER_ID" ]; then
    echo "Peer ID: $PEER_ID"
  else
    echo "Peer ID: (nieznany — binarka nie zwróciła w tym trybie; klucz istnieje)"
  fi
  echo
  echo "[PRIVATE NODE-KEY BACKUP]"
  echo "(Ten klucz służy tylko do identyfikacji węzła P2P – NIE używać jako rewards key!)"
  echo "Ścieżka: $PEER_FILE"
  echo
  echo "→ HEX:"
  xxd -p "$PEER_FILE" | tr -d '\n'
  echo
  echo
  echo "→ BASE64:"
  base64 -w0 "$PEER_FILE"
  echo
  echo "=============================================================="
  echo
} >> "$KEYS_FILE"

chmod 600 "$KEYS_FILE"

# ────────────────────────────────────────────────────────────────
# 9) Zapis flag do /etc/quantus.env (bez wtrącania rewards; zostawiamy Ci wybór)
# ────────────────────────────────────────────────────────────────
say "⚙️  Zapisuję flagi do /etc/quantus.env..."
cat >/etc/quantus.env <<EOF
# Quantus Dirac node flags
QUANTUS_NODE_FLAGS=${QUANTUS_NODE_FLAGS}
# Chain spec: --chain /root/chain/dirac.raw.json  (jeśli istnieje)
# (Opcjonalnie) możesz dodać:
#   --rewards-address ${REWARDS_ADDR:-<wstaw_adres>}
EOF

# ────────────────────────────────────────────────────────────────
# 10) Weryfikacja
# ────────────────────────────────────────────────────────────────
say "✅  Weryfikuję wersje..."
$NODE_BIN --version || true
$MINER_BIN --version || true

echo -e "\n\e[1m✅ Migracja zakończona.\e[0m"
echo "Backup:   $BACKUP_ROOT"
echo "Node:     $NODE_BIN"
echo "Miner:    $MINER_BIN"
echo "Spec:     $CHAIN_DIR/dirac.raw.json (jeśli wygenerowany)"
echo "Keys out: $KEYS_FILE"
if [ -n "${REWARDS_ADDR:-}" ]; then
  echo "Rewards Address (nowe konto): $REWARDS_ADDR"
fi
