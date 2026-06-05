#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 6.5 (SUPER FAST LOGCAT STREAMER)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=5
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

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
    log "🚀 Join private server Grow a Garden..."
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 3
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

# ─────────────────────────────────────────
#    CORE MONITOR JALUR CEPAT (REAL-TIME)
# ─────────────────────────────────────────
monitor_logcat_dc() {
    # Pantau logcat secara real-time. Begitu teks di bawah ini muncul, langsung eksekusi!
    logcat -v time 2>/dev/null | grep --line-buffered -iE "Connection lost|Lost connection with reason|Disconnect error|Error code: 288|288|shutdown" | while read -r line; do
        
        NOW=$(date +%s)
        GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
        
        # Jaga-jaga agar tidak memotong proses server hop Delta (Masa aman 3 menit)
        if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then
            continue
        fi
        
        log "🚨 LOGCAT MATCH: Terdeteksi Sinyal DC Game ($line)"
        log "♻️ Rejoin otomatis dipicu sekarang juga!"
        
        join_private_server
        sleep 20
    done
}

start_monitor() {
    kill "$MONITOR_PID" 2>/dev/null
    sleep 1
    logcat -c
    sleep 1
    monitor_logcat_dc &
    MONITOR_PID=$!
    log "🔍 Monitor DC Real-time Aktif (PID: $MONITOR_PID)"
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
echo "    ROBLOX RECONNECT v6.5 (FAST LOGCAT)   "
echo "========================================="
log "URL: $URL"
echo "========================================="

join_private_server
sleep 20
start_monitor

while true; do
    NOW=$(date +%s)
    
    # Cek kasat mata: Apakah proses Roblox-nya mati total (crash ke home)
    if ! pidof "$PKG" > /dev/null 2>&1 && ! ps -A 2>/dev/null | grep -q "$PKG"; then
        log "💥 Roblox mati/tertutup! Mengembalikan ke game..."
        join_private_server
        sleep 20
        start_monitor
        continue
    fi
    
    # Cek berkala untuk relog per jam
    LAST_RELOG=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    if [ $((NOW - LAST_RELOG)) -ge $((RELOG_SETIAP_JAM * 3600)) ]; then
        log "🔄 Jadwal relog berkala tiba..."
        join_private_server
        sleep 20
        start_monitor
        continue
    fi

    sleep "$CHECK_INTERVAL"
done
