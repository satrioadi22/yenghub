#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 7.0 (ANTI FREEZE CLOUD ENGINE)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=8
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

STATE_DIR="/data/local/tmp/rbx_state"
FILE_LAST_RELOG="$STATE_DIR/last_relog"
FILE_GRACE_UNTIL="$STATE_DIR/grace_until"

TELEPORT_GRACE=180

# Mencegah CPU Android Cloud tidur (Sangat Penting untuk Redfinger!)
echo "latency" > /sys/power/wake_lock 2>/dev/null
chmod 666 /sys/power/wake_lock 2>/dev/null

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
save_config() { echo -e "URL=\"$URL\"\nRELOG_SETIAP_JAM=$RELOG_SETIAP_JAM" > "$CONFIG_FILE"; }
clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }
log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

join_private_server() {
    log ""
    log "🚀 Mengaktifkan ulang window manager cloud..."
    wm dismiss-keyguard 2>/dev/null # Membuka paksa jika ada layar freeze/lockscreen cloud
    
    log "🚀 Join private server Grow a Garden..."
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

wait_for_ingame() {
    log "👀 Menunggu loading game (25 detik)..."
    sleep 25
}

# ─────────────────────────────────────────
#    MAIN LOOP ENGINE (DENGAN DETEKSI ABSOLUT)
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
echo "    ROBLOX RECONNECT v7.0 (ANTI-FREEZE)   "
echo "========================================="
log "URL: $URL"
echo "========================================="

join_private_server
wait_for_ingame

while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
    
    # 1. CEK INDIKATOR PROSES (JALUR UTAMA JIKA ROBLOX CRASH/MATI)
    if ! pidof "$PKG" > /dev/null 2>&1 && ! ps -A 2>/dev/null | grep -q "$PKG"; then
        log "💥 Roblox terdeteksi Mati/Crash setelah Pengalaman Virtual Terputus!"
        log "♻️ Melakukan Rejoin Paksa..."
        join_private_server
        wait_for_ingame
        continue
    fi

    # 2. DETEKSI EMBEDDED LOGCAT (KHUSUS ERROR 288 / DISCONNECT)
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        # Cek apakah 50 baris logcat terakhir mencatat adanya error putus koneksi
        if logcat -d -t 50 2>/dev/null | grep -qiE "Connection lost|Lost connection|288|shutdown|kick|Disconnect"; then
            log "🚨 LOG DETECTED: Log sistem mencatat kode 288 / Sinyal terputus!"
            log "♻️ Eksekusi Force Close & Rejoin ke Private Server..."
            logcat -c # Bersihkan log lama biar ga terbaca berulang
            join_private_server
            wait_for_ingame
            continue
        fi
        
        # 3. DETEKSI DUMPSYS WINDOWS TERBARU (ANTI GAGAL CLOUD)
        # Jika window manager mendeteksi ada dialog/error atau stuck, langsung sikat!
        if dumpsys window 2>/dev/null | grep -q "$PKG" && dumpsys window 2>/dev/null | grep -qiE "error|dialog|popup|alert"; then
            log "⚠️ VISUAL WARNING: Terdeteksi jendela dialog error 288 membeku!"
            sleep 5
            # Cek sekali lagi buat mastiin bukan loading map
            if dumpsys window 2>/dev/null | grep -qiE "error|dialog|popup|alert"; then
                log "♻️ Jendela error valid menetap permanen. Rejoin sekarang!"
                join_private_server
                wait_for_ingame
                continue
            fi
        fi
    fi
    
    # 4. CEK TIMER RELOG BERKALA
    LAST_RELOG=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    if [ $((NOW - LAST_RELOG)) -ge $((RELOG_SETIAP_JAM * 3600)) ]; then
        log "🔄 Jadwal relog berkala (1 Jam) terpenuhi. Memulai ulang..."
        join_private_server
        wait_for_ingame
        continue
    fi

    sleep "$CHECK_INTERVAL"
done
