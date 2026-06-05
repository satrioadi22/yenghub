#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 5.5 (GOLDEN EDITION - v3.5 REMASTERED)
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

clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }

header() {
    echo "========================================="
    echo "    ROBLOX AUTO RECONNECT v5.5 (FIXED)"
    echo "========================================="
}

show_toggle() {
    if [ "$1" = "1" ]; then echo "ON"; else echo "OFF"; fi
}

show_current_config() {
    echo ""
    echo "  URL    : ${URL:-[belum diisi]}"
    echo "  Relog  : ${RELOG_SETIAP_JAM} jam"
    echo "  Reconnect otomatis : $(show_toggle $RECONNECT_OTOMATIS)"
    echo "  Restart kalau crash: $(show_toggle $RESTART_KALAU_CRASH)"
    echo ""
}

# ─────────────────────────────────────────
#    WIZARD SETUP & MENU
# ─────────────────────────────────────────

wizard_setup() {
    clr; header; echo ""
    while true; do
        echo "  Paste link private server Roblox kamu:"
        printf "  > "
        read -r URL
        if [ -n "$URL" ]; then break; fi
        echo "  ⚠ URL tidak boleh kosong!"; echo ""
    done
    RELOG_SETIAP_JAM=1; RECONNECT_OTOMATIS=1; RESTART_KALAU_CRASH=1; RECONNECT_SAAT_HOME=0
    save_config; echo ""; echo "  ✅ Config tersimpan!"; sleep 1
}

menu_utama() {
    while true; do
        clr; header; show_current_config
        echo "  1) Langsung jalanin"
        echo "  2) Ganti URL private server"
        echo "  3) Keluar"
        echo ""
        printf "  Pilih (1-3): "
        read -r PILIHAN
        case $PILIHAN in
            1) return 0 ;;
            2) 
                echo ""; echo "Paste URL baru:"; printf "> "; read -r NEW_URL
                if [ -n "$NEW_URL" ]; then URL="$NEW_URL"; save_config; fi ;;
            3) exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-3"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI CORE LOGIC (V3.5 ENGINE)
# ─────────────────────────────────────────

cek_apakah_terhubung() {
    if pidof "$PKG" > /dev/null 2>&1 || ps -A 2>/dev/null | grep -q "$PKG"; then
        return 0 
    else
        return 1 
    fi
}

log() {
    echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"
}

join_private_server() {
    log ""
    log "🚀 Join private server Grow a Garden..."
    echo "1" > "$FILE_RECONNECTING"
    
    # Kunci Masa Aman 180 Detik (3 Menit) agar tidak diganggu saat loading / hop market
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"

    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

wait_for_ingame() {
    log "👀 Menunggu INGAME..."
    sleep 20
    echo "0" > "$FILE_RECONNECTING"
}

monitor_disconnect() {
    log "🔍 Monitor DC aktif..."
    echo "0" > "$FILE_IN_BACKGROUND"

    while read -r line; do
        if echo "$line" | grep -qi "foregroundActivities=false" && echo "$line" | grep -q "$PKG"; then
            echo "1" > "$FILE_IN_BACKGROUND"
            log "📱 App masuk background"
            continue
        fi

        if echo "$line" | grep -qi "foregroundActivities=true" && echo "$line" | grep -q "$PKG"; then
            sleep 5
            echo "0" > "$FILE_IN_BACKGROUND"
            log "📱 App kembali foreground"
            continue
        fi

        DC_DETECTED=0
        DC_REASON=""

        # Logcat check untuk error keras
        if echo "$line" | grep -qiE "Error code: 288|Disconnect error: 288|kick|shutdown"; then
            DC_DETECTED=1
            DC_REASON="Server Shutdown / Pop-up Koneksi Terputus (Error 288)"
        fi
        
        if echo "$line" | grep -qi "Sending disconnect with reason"; then
            # AMANKAN SERVER HOP MARKET TRADE AGAR TIDAK DI-BEGAL SCRIPT
            if echo "$line" | grep -qiE "teleport|hop|leave|transfer"; then 
                log "🔄 Delta melakukan Server Hop ke Market Trade... Aman, dibiarkan."
                continue 
            fi
            DC_DETECTED=1
            DC_REASON="Sending disconnect (Logcat Client)"
        fi

        if [ "$DC_DETECTED" -eq 1 ]; then
            NOW=$(date +%s)
            GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
            
            # Jika masih dalam masa aman teleport, jangan di-kick balik ke Garden
            if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then 
                continue 
            fi

            log "🚨 PERINGATAN: $DC_REASON Terdeteksi!"
            log "♻️ Menutup paksa game dan kembali masuk ke Private Server Garden..."
            join_private_server
            wait_for_ingame
            continue
        fi

    done < <(logcat -v time 2>/dev/null | grep --line-buffered -iE \
        "Sending disconnect with reason|Connection lost|Lost connection with reason|Disconnected from server for reason|foregroundActivities=|288|shutdown|kick")
}

start_monitor() {
    kill "$MONITOR_PID" 2>/dev/null
    sleep 1
    logcat -c
    sleep 1
    monitor_disconnect &
    MONITOR_PID=$!
}

check_relog_needed() {
    [ "$RELOG_SETIAP_JAM" = "0" ] && return 1
    local NOW; NOW=$(date +%s)
    local LAST; LAST=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    [ $((NOW - LAST)) -ge $((RELOG_SETIAP_JAM * 3600)) ]
}

cleanup() {
    log "🛑 Script dihentikan."
    kill "$MONITOR_PID" 2>/dev/null
    rm -rf "$STATE_DIR"
    exit 0
}
trap cleanup INT TERM

# ─────────────────────────────────────────
#    MAIN EXECUTION
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then
    echo "⚠️ Minta akses root..."
    exec su -c "$0"
fi

default_config; load_config
if [ -z "$URL" ]; then wizard_setup; else menu_utama; fi

mkdir -p "$STATE_DIR"
echo "0" > "$FILE_LAST_RECONNECT"
echo "0" > "$FILE_IN_BACKGROUND"
echo "0" > "$FILE_RECONNECTING"

clr
header
log "URL              : $URL"
echo "========================================="

join_private_server
wait_for_ingame
start_monitor

while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)

    # 1. CEK ROBOT/ROBLOX CRASH MATI TOTAL
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
            log "💥 Roblox tertutup/crash! Restart kembali ke Private Server..."
            sleep 3
            join_private_server
            wait_for_ingame
            start_monitor
            continue
        fi
    fi

    # 2. DETEKSI VISUAL POP-UP (FITUR ANDALAN LU DI V3.5)
    # Lapis pengaman layar visual ini hanya aktif jika Grace Period (180 detik) sudah habis!
    # Jadi pas Delta lagi loading pindah Market, dia aman ga bakal ketendang.
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        if dumpsys window 2>/dev/null | grep -q "$PKG" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error"; then
            
            # Verifikasi 7 detik untuk memastikan pop-up tersebut bukan loading map biasa
            sleep 7
            if dumpsys window 2>/dev/null | grep -q "$PKG" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error"; then
                log "⚠️ VISUAL DETECTED: Terdeteksi pop-up membeku di layar (Error 288 / Terputus)!"
                log "♻️ Eksekusi Force Close & Rejoin ke Private Server Garden..."
                am force-stop "$PKG"
                sleep 3
                join_private_server
                wait_for_ingame
                start_monitor
                continue
            fi
        fi
    fi

    if check_relog_needed; then
        log "🔄 Relog otomatis berkala..."
        join_private_server
        wait_for_ingame
        start_monitor
        continue
    fi

    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Roblox running"
        LAST_VERBOSE=$NOW
    fi

    sleep "$CHECK_INTERVAL"
done
