#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 6.0 (HYBRID LOGIC - TELEPORT & SHUTDOWN FIX)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=10
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

STATE_DIR="/data/local/tmp/rbx_state"
FILE_LAST_RECONNECT="$STATE_DIR/last_reconnect"
FILE_IN_BACKGROUND="$STATE_DIR/in_background"
FILE_LAST_RELOG="$STATE_DIR/last_relog"
FILE_RECONNECTING="$STATE_DIR/reconnecting"
FILE_GRACE_UNTIL="$STATE_DIR/grace_until"

RECONNECT_COOLDOWN=45
TELEPORT_GRACE=180
MONITOR_PID=""
LAST_VERBOSE=0
VERBOSE_INTERVAL=600

# ─────────────────────────────────────────
#    FUNGSI CONFIG
# ─────────────────────────────────────────

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
# ─────────────────────────────────────────
#    CONFIG ROBLOX AUTO RECONNECT
# ─────────────────────────────────────────
URL="$URL"
RELOG_SETIAP_JAM=$RELOG_SETIAP_JAM
RECONNECT_OTOMATIS=$RECONNECT_OTOMATIS
RESTART_KALAU_CRASH=$RESTART_KALAU_CRASH
RECONNECT_SAAT_HOME=$RECONNECT_SAAT_HOME
EOF
}

default_config() {
    URL=""
    RELOG_SETIAP_JAM=1
    RECONNECT_OTOMATIS=1
    RESTART_KALAU_CRASH=1
    RECONNECT_SAAT_HOME=0
}

# ─────────────────────────────────────────
#    FUNGSI TAMPILAN & SETUP
# ─────────────────────────────────────────

clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }

header() {
    echo "========================================="
    echo "    ROBLOX AUTO RECONNECT v6.0 (HYBRID)"
    echo "========================================="
}

show_toggle() {
    local val=$1
    if [ "$val" = "1" ]; then echo "ON"; else echo "OFF"; fi
}

show_current_config() {
    echo ""
    echo "  URL    : ${URL:-[belum diisi]}"
    echo "  Restart kalau crash: $(show_toggle $RESTART_KALAU_CRASH)"
    echo ""
}

wizard_setup() {
    clr
    header
    echo ""
    while true; do
        echo "  Paste link private server Roblox kamu:"
        printf "  > "
        read -r URL
        if [ -n "$URL" ]; then break; fi
        echo "  ⚠ URL tidak boleh kosong!"
        echo ""
    done
    
    RELOG_SETIAP_JAM=0
    RECONNECT_OTOMATIS=0
    RESTART_KALAU_CRASH=1
    RECONNECT_SAAT_HOME=0
    save_config
    echo ""
    echo "  ✅ Config tersimpan!"
    sleep 1
}

menu_utama() {
    while true; do
        clr
        header
        show_current_config
        echo "  1) Langsung jalanin bot"
        echo "  2) Ganti URL private server"
        echo "  3) Keluar"
        echo ""
        printf "  Pilih (1-3): "
        read -r PILIHAN

        case $PILIHAN in
            1) return 0 ;;
            2) 
                echo ""
                echo "  Paste URL baru:"
                printf "  > "
                read -r NEW_URL
                if [ -n "$NEW_URL" ]; then URL="$NEW_URL"; save_config; fi
                ;;
            3) exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-3"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI CORE
# ─────────────────────────────────────────

log() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"
}

join_private_server() {
    log ""
    log "🚀 Launching Private Server Garden..."
    
    # Beri proteksi waktu aman (180 detik) agar tidak terganggu proses loading awal
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Roblox diluncurkan. Menunggu Delta memindahkan akun ke Market..."
}

# MONITOR BACKGROUND & LOGCAT SHUTDOWN SECARA REALTIME
monitor_logcat_hybrid() {
    while read -r line; do
        # 1. Cek status background app
        if echo "$line" | grep -qi "foregroundActivities=false" && echo "$line" | grep -q "$PKG"; then
            echo "1" > "$FILE_IN_BACKGROUND"
            log "📱 App masuk background"
            continue
        fi
        if echo "$line" | grep -qi "foregroundActivities=true" && echo "$line" | grep -q "$PKG"; then
            sleep 3
            echo "0" > "$FILE_IN_BACKGROUND"
            log "📱 App kembali foreground"
            continue
        fi

        # 2. DETEKSI AKURAT ERROR 288 / SHUTDOWN (Logcat ga bakalan meleset)
        if echo "$line" | grep -qiE "288|shutdown"; then
            # Ambil timestamp saat ini untuk validasi grace period
            local NOW; NOW=$(date +%s)
            local GRACE; GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
            
            # Jika tulisan shutdown muncul SETELAH lewat masa loading awal (artinya pas udah di Market)
            if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
                log "🚨 KATA KUNCI DISCONNECT TERDETEKSI: $line"
                log "🚨 POSITIF: Server Market Trade mengalami Shutdown / Error 288!"
                log "♻️ Mengeksekusi Rejoin ke Private Server Garden..."
                
                # Panggil rejoin langsung dari background monitor
                join_private_server
            fi
        fi
    done < <(logcat -v time 2>/dev/null | grep --line-buffered -iE "foregroundActivities=|288|shutdown")
}

cleanup() {
    log "🛑 Script dihentikan."
    kill "$MONITOR_PID" 2>/dev/null
    rm -rf "$STATE_DIR"
    exit 0
}
trap cleanup INT TERM

# ─────────────────────────────────────────
#    MAIN PROGRAM
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then
    echo "⚠️ Minta akses root..."
    exec su -c "$0"
fi

default_config
load_config

if [ -z "$URL" ]; then
    wizard_setup
else
    menu_utama
fi

mkdir -p "$STATE_DIR"
echo "0" > "$FILE_IN_BACKGROUND"

clr
header
log "Bot Mode: HYBRID DETECTOR (ANTI-BEGAL DELTA)"
log "URL: $URL"
echo "========================================="

join_private_server

# Jalankan pendeteksi logcat di background process
logcat -c
monitor_logcat_hybrid &
MONITOR_PID=$!

while true; do
    sleep "$CHECK_INTERVAL"
    
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)

    # 1. CEK APAKAH ROBLOX CRASH / MATI TOTAL
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
            log "💥 Roblox tertutup/crash! Mengembalikan ke Private Server..."
            join_private_server
            continue
        fi
    fi

    # Info log berkala biar lu tau scriptnya ga mati
    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Roblox terpantau aman dan berjalan."
        LAST_VERBOSE=$NOW
    fi
done
