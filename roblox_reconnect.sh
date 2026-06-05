#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 3.5 (FIXED LOGIC - ANTI STUCK 288)
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
#    Edit angka: 1 = ON, 0 = OFF
# ─────────────────────────────────────────

URL="$URL"

# Relog otomatis setiap X jam (0 = mati)
RELOG_SETIAP_JAM=$RELOG_SETIAP_JAM

# Reconnect otomatis saat disconnect (1=ON / 0=OFF)
RECONNECT_OTOMATIS=$RECONNECT_OTOMATIS

# Restart otomatis kalau Roblox crash (1=ON / 0=OFF)
RESTART_KALAU_CRASH=$RESTART_KALAU_CRASH

# Reconnect saat app di-home/background (1=ON / 0=OFF)
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
#    FUNGSI TAMPILAN
# ─────────────────────────────────────────

clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }

header() {
    echo "========================================="
    echo "    ROBLOX AUTO RECONNECT + AUTO RELOG"
    echo "========================================="
}

show_toggle() {
    if [ "$1" = "1" ]; then echo "ON"; else echo "OFF"; fi
}

show_current_config() {
    echo ""
    echo "  URL    : ${URL:-[belum diisi]}"
    echo "  Relog  : ${RELOG_SETIAP_JAM} jam $([ "$RELOG_SETIAP_JAM" = "0" ] && echo '(OFF)' || echo '(ON)')"
    echo "  Reconnect otomatis : $(show_toggle $RECONNECT_OTOMATIS)"
    echo "  Restart kalau crash: $(show_toggle $RESTART_KALAU_CRASH)"
    echo "  Reconnect saat home: $(show_toggle $RECONNECT_SAAT_HOME)"
    echo ""
}

# ─────────────────────────────────────────
#    WIZARD SETUP PERTAMA KALI
# ─────────────────────────────────────────

wizard_setup() {
    clr
    header
    echo ""
    echo "  Halo! Config belum ada, mari setup dulu."
    echo ""

    while true; do
        echo "  Paste link private server Roblox kamu:"
        printf "  > "
        read -r URL
        if [ -n "$URL" ]; then break; fi
        echo "  ⚠ URL tidak boleh kosong!"
        echo ""
    done

    echo ""
    echo "  Relog otomatis setiap berapa jam? (0=OFF, default: 1)"
    printf "  > "
    read -r INPUT_RELOG
    if [[ "$INPUT_RELOG" =~ ^[0-9]+$ ]]; then RELOG_SETIAP_JAM=$INPUT_RELOG; else RELOG_SETIAP_JAM=1; fi

    echo ""
    echo "  Reconnect otomatis saat DC? (1=ON / 0=OFF, default: 1)"
    printf "  > "
    read -r INPUT_RC
    if [ "$INPUT_RC" = "0" ]; then RECONNECT_OTOMATIS=0; else RECONNECT_OTOMATIS=1; fi

    echo ""
    echo "  Restart otomatis kalau Roblox crash? (1=ON / 0=OFF, default: 1)"
    printf "  > "
    read -r INPUT_CR
    if [ "$INPUT_CR" = "0" ]; then RESTART_KALAU_CRASH=0; else RESTART_KALAU_CRASH=1; fi

    echo ""
    echo "  Reconnect saat app di-minimize/home? (1=ON / 0=OFF, default: 0)"
    printf "  > "
    read -r INPUT_RH
    if [ "$INPUT_RH" = "1" ]; then RECONNECT_SAAT_HOME=1; else RECONNECT_SAAT_HOME=0; fi

    save_config
    echo ""
    echo "  ✅ Config tersimpan!"
    sleep 1
}

# ─────────────────────────────────────────
#    MENU UTAMA
# ─────────────────────────────────────────

menu_utama() {
    while true; do
        clr
        header
        show_current_config
        echo "  Mau ngapain?"
        echo ""
        echo "  1) Langsung jalanin"
        echo "  2) Ganti URL private server"
        echo "  3) Ubah setting (relog, reconnect, dll)"
        echo "  4) Keluar"
        echo ""
        printf "  Pilih (1-4): "
        read -r PILIHAN

        case $PILIHAN in
            1) return 0 ;;
            2) menu_ganti_url ;;
            3) menu_edit_setting ;;
            4) echo ""; echo "  Sampai jumpa!"; exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-4"; sleep 1 ;;
        esac
    done
}

menu_ganti_url() {
    clr; header; echo ""
    echo "  URL saat ini: ${URL:-[kosong]}"
    echo ""
    echo "  Paste URL baru (Enter untuk batal):"
    printf "  > "
    read -r NEW_URL
    if [ -n "$NEW_URL" ]; then
        URL="$NEW_URL"
        save_config
        echo -e "\n  ✅ URL diperbarui!"
    else
        echo -e "\n  Dibatalkan."
    fi
    sleep 1
}

menu_edit_setting() {
    while true; do
        clr; header; echo -e "\n  ── EDIT SETTING ──────────────────────\n"
        echo "  1) Relog otomatis : ${RELOG_SETIAP_JAM} jam $([ "$RELOG_SETIAP_JAM" = "0" ] && echo '(OFF)' || echo '(ON)')"
        echo "  2) Reconnect otomatis  : $(show_toggle $RECONNECT_OTOMATIS)"
        echo "  3) Restart kalau crash : $(show_toggle $RESTART_KALAU_CRASH)"
        echo "  4) Reconnect saat home : $(show_toggle $RECONNECT_SAAT_HOME)"
        echo "  5) Kembali ke menu utama"
        echo ""
        printf "  Pilih (1-5): "
        read -r PILIHAN

        case $PILIHAN in
            1)
                echo -e "\n  Relog setiap berapa jam? (0 = matikan relog):"
                printf "  > "
                read -r V
                if [[ "$V" =~ ^[0-9]+$ ]]; then RELOG_SETIAP_JAM=$V; save_config; echo "  ✅ Disimpan!"; else echo "  ⚠ Masukkan angka!"; fi
                sleep 1 ;;
            2)
                echo -e "\n  Reconnect otomatis (1=ON / 0=OFF):"
                printf "  > "
                read -r V
                if [ "$V" = "0" ] || [ "$V" = "1" ]; then RECONNECT_OTOMATIS=$V; save_config; echo "  ✅ Disimpan!"; else echo "  ⚠ Masukkan 0 atau 1!"; fi
                sleep 1 ;;
            3)
                echo -e "\n  Restart kalau crash (1=ON / 0=OFF):"
                printf "  > "
                read -r V
                if [ "$V" = "0" ] || [ "$V" = "1" ]; then RESTART_KALAU_CRASH=$V; save_config; echo "  ✅ Disimpan!"; else echo "  ⚠ Masukkan 0 atau 1!"; fi
                sleep 1 ;;
            4)
                echo -e "\n  Reconnect saat home (1=ON / 0=OFF):"
                printf "  > "
                read -r V
                if [ "$V" = "0" ] || [ "$V" = "1" ]; then RECONNECT_SAAT_HOME=$V; save_config; echo "  ✅ Disimpan!"; else echo "  ⚠ Masukkan 0 atau 1!"; fi
                sleep 1 ;;
            5) return ;;
            *) echo "  ⚠ Pilih 1-5"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI CORE
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
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"

    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

wait_for_ingame() {
    log "👀 Menunggu INGAME (max 90s)..."
    local FOUND=0

    while read -r line; do
        if echo "$line" | grep -qi "Connection accepted from"; then
            IP=$(echo "$line" | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)
            log "✅ INGAME! Server IP: $IP"
            FOUND=1
            termux-vibrate -d 300 2>/dev/null
            break
        fi
    done < <(timeout 90 logcat -v time 2>/dev/null | grep --line-buffered -i "Connection accepted from")

    if [ "$FOUND" -eq 0 ]; then
        log "⏱️ Timeout - retry join..."
        sleep 3
        am force-stop "$PKG"
        sleep 3
        am start -a android.intent.action.VIEW -d "$URL" "$PKG"
        log "🔄 Retry join, menunggu 90s..."

        while read -r line; do
            if echo "$line" | grep -qi "Connection accepted from"; then
                IP=$(echo "$line" | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)
                log "✅ INGAME! Server IP: $IP"
                FOUND=1
                termux-vibrate -d 300 2>/dev/null
                break
            fi
        done < <(timeout 90 logcat -v time 2>/dev/null | grep --line-buffered -i "Connection accepted from")

        [ "$FOUND" -eq 0 ] && log "⏱️ Retry timeout - lanjut monitoring..."
    fi

    echo "0" > "$FILE_RECONNECTING"
}

monitor_disconnect() {
    log "🔍 Monitor DC aktif (PID: $$)"
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

        # ──────────────────────────────────────────────────
        # DETEKSI UTAMA HOP MARKET (BIAR AMAN DAN TIDAK REJOIN)
        # ──────────────────────────────────────────────────
        if echo "$line" | grep -qiE "teleport|hop|leave|transfer|Sending disconnect with reason 12"; then 
            log "🔄 Delta memicu Server Hop ke Market Trade... Berikan Masa Aman!"
            echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"
            continue 
        fi

        DC_DETECTED=0
        DC_REASON=""

        # LOGIKA DETEKSI 1: Pop-up Terputus (Error 288) -> JALUR PRIORITAS UTAMA
        if echo "$line" | grep -qiE "Error code: 288|Disconnect error: 288|Connection lost|Lost connection with reason|Disconnected from server for reason|shutdown|kick"; then
            
            # Cek dulu apakah game lu lagi dalam masa aman Server Hop Market?
            NOW=$(date +%s)
            GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
            if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then
                # Jika masih dalam masa aman pindah server, abaikan log DC ini agar tidak maksa balik ke Garden!
                continue
            fi

            DC_DETECTED=1
            DC_REASON="Pop-up Koneksi Terputus (Error 288)"
        fi

        if [ "$DC_DETECTED" -eq 1 ]; then
            log "🚨 PERINGATAN CRITICAL: $DC_REASON Terdeteksi!"
            log "♻️ Mengeksekusi Rejoin Instan ke Private Server Garden..."
            
            echo "0" > "$FILE_RECONNECTING"
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
    log "✅ Monitor started (PID: $MONITOR_PID)"
}

check_relog_needed() {
    [ "$RELOG_SETIAP_JAM" = "0" ] && return 1
    local NOW; NOW=$(date +%s)
    local LAST; LAST=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    local ELAPSED=$((NOW - LAST))
    local RELOG_SECONDS=$((RELOG_SETIAP_JAM * 3600))
    [ "$ELAPSED" -ge "$RELOG_SECONDS" ]
}

cleanup() {
    log "🛑 Script dihentikan."
    kill "$MONITOR_PID" 2>/dev/null
    rm -rf "$STATE_DIR"
    exit 0
}
trap cleanup INT TERM

# ─────────────────────────────────────────
#    MAIN — CEK ROOT
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then
    echo "⚠️ Minta akses root..."
    exec su -c "$0"
fi

# ─────────────────────────────────────────
#    MAIN — LOAD CONFIG
# ─────────────────────────────────────────

default_config
load_config

if [ -z "$URL" ] && [ ! -f "$CONFIG_FILE" ]; then
    wizard_setup
    load_config
else
    menu_utama
    load_config
fi

# ─────────────────────────────────────────
#    JALANIN SCRIPT
# ─────────────────────────────────────────

mkdir -p "$STATE_DIR"
echo "0" > "$FILE_LAST_RECONNECT"
echo "0" > "$FILE_IN_BACKGROUND"
echo "$(date +%s)" > "$FILE_LAST_RELOG"
echo "0" > "$FILE_RECONNECTING"

clr
echo "=========================================" | tee -a "$LOG_FILE"
echo "    ROBLOX AUTO RECONNECT + AUTO RELOG"    | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
log "URL              : $URL"
log "Relog            : setiap ${RELOG_SETIAP_JAM} jam    → $([ "$RELOG_SETIAP_JAM" = "0" ] && echo OFF || echo ON)"
log "Reconnect        : DC detection  → $(show_toggle $RECONNECT_OTOMATIS)"
log "Restart crash    : auto restart  → $(show_toggle $RESTART_KALAU_CRASH)"
log "Reconnect@home   : saat home     → $(show_toggle $RECONNECT_SAAT_HOME)"
log "Log file         : $LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo ""

join_private_server
wait_for_ingame

log "🔍 Monitoring aktif..."
echo "-----------------------------------------" | tee -a "$LOG_FILE"

start_monitor

while true; do

    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)

    # RESTART KALAU CRASH (Proses Roblox hilang dari memori)
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
            
            # AMAN: Jika roblox mati karena sedang proses Server Hop Market, abaikan status crash ini!
            if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then
                sleep 5
                continue
            fi

            log "💥 Roblox crash asli! Restart..."
            sleep 3
            join_private_server
            wait_for_ingame
            start_monitor
            continue
        fi
    fi

    # ──────────────────────────────────────────────────
    # BACKUP VISUAL SECURE LOGIC
    # ──────────────────────────────────────────────────
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        if dumpsys window 2>/dev/null | grep -q "$PKG" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error"; then
            sleep 5
            if dumpsys window 2>/dev/null | grep -q "$PKG" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error"; then
                log "⚠️ Terdeteksi pop-up stuck permanen di layar (Error 288 / Terputus). Force Rejoin!"
                am force-stop "$PKG"
                sleep 3
                join_private_server
                wait_for_ingame
                start_monitor
                continue
            fi
        fi
    fi
    # ──────────────────────────────────────────────────

    if check_relog_needed; then
        log "🔄 Relog setiap ${RELOG_SETIAP_JAM} jam..."
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
