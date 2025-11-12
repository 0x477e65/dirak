# 🚀 Quantus – Dirac Testnet Update (Node + Miner)

Ten projekt zawiera zestaw skryptów pozwalających szybko zaktualizować node i minera  
do najnowszej wersji **Quantus Dirac Testnet (v0.4.x)**.

---

## 📂 Zawartość repo

- **migracja-dirac.sh** – pełna aktualizacja, build node/miner, backup, generacja kluczy  
- **node-start.sh** – automatyczny start noda (tmux + watchdog)  
- **miner-start.sh** – automatyczny start minera (tmux + watchdog)

---

## 📥 Instalacja

```bash
git clone https://github.com/0x477e65/dirak.git
cd dirak
chmod +x migracja-dirac.sh node-start.sh miner-start.sh
```

## 🔧 Migracja na Dirac

```bash
./migracja-dirac.sh
```

## Skrypt automatycznie: 

zatrzyma stare procesy Quantus,

wykona pełny update systemu i zainstaluje zależności,

skompiluje quantus-node v0.4.x oraz quantus-miner v1.0.x,

zrobi backup danych ze starego testnetu,

wygeneruje nowy klucz konta (rewards),

wygeneruje klucz sieciowy (peer-id / secret_dilithium),

zapisze wszystkie klucze do jednego pliku.

## 🔐 Gdzie znajdują się klucze?
```bash
/root/keys-dirac.txt
```
Zrób `seeee` backup! ;)

## Plik zawiera:

`mnemonic` + `seed` + `SS58 Address` _(konto do nagród)_, `Peer ID`, `private node-key` _(HEX + Base64)_.

### ⚠️ Stary adres SS58 z testnetu Schrödinger NIE działa w Dirac (inna kryptografia).
Musisz używać nowo wygenerowanego adresu rewards.

## ▶️ Uruchamianie noda i minera

```bash
./node-start.sh
tmux attach -t quantus-node
```

**Miner:**
```bash
./miner-start.sh
tmux attach -t quantus-miner
```
