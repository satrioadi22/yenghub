#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 8.0 (ROBLOX LOG-FILE TAILER ENGINE)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=5
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

# Jalur folder log internal Roblox di Android
ROBLOX_LOG_DIR="/storage/emulated/0/Android/data/com.roblox.client/files/logs"

STATE_DIR="/data/local/tmp/rbx_state"
FILE_LAST_RELOG="$STATE_DIR/last_relog"
FILE_GRACE_UNTIL="$STATE_DIR/grace_until"

TELEPORT_GRACE=180
MONITOR_PID=""

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
save_config() { echo -e "URL=\"$URL\"\nRELOG_SETIAP_JAM=$RELOG_SETIAP_JAM" > "$CONFIG_FILE"; }
clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }
log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

join_private_server() {
    log ""
    log "🚀 Menyapu sisa log lama..."
    rm -rf "$ROBLOX_LOG_DIR"/* 2>/dev/null # Bersihkan log lama biar ga rancu

    log "🚀 Join private server Grow a Garden..."
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

# ─────────────────────────────────────────
#    CORE ENGINE: MEMANTAU FILE LOG ROBLOX
# ─────────────────────────────────────────
monitor_roblox_log_file() {
    log "🔍 Mencari file log Roblox terbaru..."
    sleep 15 # Tunggu game bikin file log baru setelah start
    
    # Ambil file .log yang paling baru dibuat oleh Roblox
    LATEST_LOG=$(ls -t "$ROBLOX_LOG_DIR"/*.log 2>/dev/null | head -n 1)
    
    if [ -z "$LATEST_LOG" ] || [ ! -f "$LATEST_LOG" ]; then
        log "⚠️ File log Roblox belum terbuat, mencoba memantau ulang..."
        return 1
    fi
    
    log "🎯 Memantau log aktif: $(basename "$LATEST_LOG")"
    
    # Baca file log secara real-time (seperti tail -f)
    tail -n 0 -f "$LATEST_LOG" 2>/dev/null | while read -r line; do
        NOW=$(date +%s)
        GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
        
        # Abaikan deteksi kalau Delta lagi proses Server Hop (Masa aman 3 menit)
        if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then
            continue
        fi
        
        # Jika file log mencatat kode error 288 atau pemutusan koneksi
        if echo "$line" | grep -qiE "Disconnect|Error code: 288|Connection lost|closed|kick|shutdown"; then
            log "🚨 LOG MATCH: Roblox mencatat pop-up Error 288 di dalam file log!"
            log "♻️ Mengeksekusi Rejoin Otomatis Sekarang!"
            join_private_server
            break # Keluar loop tail untuk pindah ke file log yang baru nanti
        fi
    done
}

# ─────────────────────────────────────────
#    MAIN RUNNER
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then echo "⚠️ Minta akses root..."; exec su -c "$0"; fi

RELOG_SETIAP_JAM=1
load_config

if [ -z "$URL" ]; then
    clr
    echo "=== SETUP URL ==="
    printf "Paste link private server kamu: "
    read -r URL
    save_config
fi

mkdir -p "$STATE_DIR"
clr
echo "========================================="
echo "   ROBLOX RECONNECT v8.0 (LOG TAILER)    "
echo "========================================="
log "URL: $URL"
echo "========================================="

join_private_server

while true; do
    NOW=$(date +%s)
    
    # 1. Jika Roblox mati total / keluar sendiri ke home
    if ! pidof "$PKG" > /dev/null 2>&1 && ! ps -A 2>/dev/null | grep -q "$PKG"; then
        log "💥 Roblox mati/tertutup! Mengembalikan ke game..."
        join_private_server
        continue
    fi
    
    # 2. Jalankan pemantau file log jika game terdeteksi hidup
    if pidof "$PKG" > /dev/null 2>&1; then
        monitor_roblox_log_file
    fi
    
    # 3. Cek berkala untuk relog per jam
    LAST_RELOG=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    if [ $((NOW - LAST_RELOG)) -ge $((RELOG_SETIAP_JAM * 3600)) ]; then
        log "🔄 Jadwal relog berkala (1 Jam) tiba..."
        join_private_server
        continue
    fi

    sleep "$CHECK_INTERVAL"
done
