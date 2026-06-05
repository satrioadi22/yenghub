#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 4.2 (FULL UTUH - DENGAN WIZARD SETUP)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=5
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

STATE_DIR="/data/local/tmp/rbx_state"
FILE_LAST_RECONNECT="$STATE_DIR/last_reconnect"
FILE_IN_BACKGROUND="$STATE_DIR/in_background"
FILE_LAST_RELOG="$STATE_DIR/last_relog"
FILE_RECONNECTING="$STATE_DIR/reconnecting"
FILE_GRACE_UNTIL="$STATE_DIR/grace_until"

RECONNECT_COOLDOWN=45
TELEPORT_GRACE=150
MONITOR_PID=""
LAST_VERBOSE=0
VERBOSE_INTERVAL=600

# ─────────────────────────────────────────
#    FUNGSI CONFIG & WIZARD
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

wizard_setup() {
    clr; header; echo ""
    while true; do
        echo "  ▶ Halo bro! Masukkan link private server Roblox kamu di bawah:"
        printf "  > "
        read -r URL
        if [ -n "$URL" ]; then break; fi
        echo "  ⚠ URL tidak boleh kosong!"
        echo ""
    done

    # Set default value sesuai setelan (0 0 1 0) kesukaan lu
    RELOG_SETIAP_JAM=1
    RECONNECT_OTOMATIS=0
    RESTART_KALAU_CRASH=1
    RECONNECT_SAAT_HOME=0

    save_config
    echo ""
    echo "  ✅ URL Private Server Berhasil Disimpan!"
    sleep 1
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

menu_utama() {
    while true; do
        clr; header
        echo "  URL    : ${URL:-[belum diisi]}"
        echo "  Setting: (RC: $RECONNECT_OTOMATIS | CRASH: $RESTART_KALAU_CRASH)"
        echo "-----------------------------------------"
        echo "  1) Langsung jalanin"
        echo "  2) Ganti URL private server"
        echo "  3) Keluar"
        echo "-----------------------------------------"
        printf "  Pilih (1-3): "
        read -r PILIHAN
        case $PILIHAN in
            1) return 0 ;;
            2) clr; echo "Paste URL Private Server baru:"; read -r URL; save_config ;;
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
    log "🚀 Join private server Grow a Garden..."
    echo "1" > "$FILE_RECONNECTING"
    
    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"

    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

wait_for_ingame() {
    log "👀 Menunggu INGAME (bawaan 40s)..."
    sleep 40
    echo "0" > "$FILE_RECONNECTING"
}

# ──────────────────────────────────────────────────────────
#   MONITOR DISCONNECT (LOGCAT UTAMA - RESPONSIP & PRESISI)
# ──────────────────────────────────────────────────────────
monitor_disconnect() {
    while read -r line; do
        NOW=$(date +%s)
        GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null || echo 0)

        # 1. DETEKSI AMAN: JIKA DELTA MAU PINDAH MAP KE MARKET
        if echo "$line" | grep -qi "Sending disconnect with reason"; then
            if echo "$line" | grep -qiE "teleport|hop|leave|transfer|market|trade"; then 
                log "🔄 Delta terdeteksi Server Hop ke Market Trade! Mengunci Masa Aman..."
                echo $(( NOW + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"
                continue 
            fi
        fi

        # Jika masa aman aktif (sedang loading market), skip semua deteksi DC di bawah ini!
        if [ "$NOW" -lt "$GRACE" ]; then
            continue
        fi

        # 2. DETEKSI REJOIN ASLI: JIKA BENERAN PUTUS KONEKSI / POP-UP ERROR 288
        if echo "$line" | grep -qiE "Error code: 288|Disconnect error: 288|kick|shutdown|Connection lost|Lost connection with reason|Disconnected from server for reason"; then
            
            log "🚨 DETEKSI AKURAT: Koneksi Terputus / Pop-up 288 Muncul!"
            log "♻️ JALUR CEPAT: Menutup game dan otomatis kembali ke Private Server..."
            
            echo "0" > "$FILE_RECONNECTING"
            join_private_server
            wait_for_ingame
            logcat -c 
            break
        fi

    done < <(logcat -v time 2>/dev/null | grep --line-buffered -iE \
        "Sending disconnect with reason|Connection lost|Lost connection with reason|Disconnected from server for reason|288|shutdown|kick")
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
    local ELAPSED=$((NOW - LAST))
    [ "$ELAPSED" -ge $((RELOG_SETIAP_JAM * 3600)) ]
}

cleanup() {
    kill "$MONITOR_PID" 2>/dev/null
    rm -rf "$STATE_DIR"
    exit 0
}
trap cleanup INT TERM

# ─────────────────────────────────────────
#    MAIN PROGRAM
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then exec su -c "$0"; fi

default_config
load_config

# JIKA FILE CONFIG BELUM ADA ATAU LINK URL KOSONG, JALANKAN SETUP LINK
if [ ! -f "$CONFIG_FILE" ] || [ -z "$URL" ]; then
    wizard_setup
    load_config
else
    menu_utama
fi

mkdir -p "$STATE_DIR"
echo "$(date +%s)" > "$FILE_LAST_RELOG"
echo "0" > "$FILE_RECONNECTING"
echo "0" > "$FILE_GRACE_UNTIL"

clr; header
log "Sistem otomatis v4.2 Aktif..."
join_private_server
wait_for_ingame
start_monitor

# ─────────────────────────────────────────
#    LOOP PENGAMAT MEMORI CRASH (WHILE TRUE)
# ─────────────────────────────────────────
while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null || echo 0)

    # RESTART KALAU CRASH (Roblox hilang dari memori secara tidak wajar)
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! pidof "$PKG" > /dev/null 2>&1; then
            
            # Jika roblox hilang karena emang lagi proses pindah ke Market, biarkan lolos!
            if [ "$NOW" -lt "$GRACE" ]; then
                sleep 5
                continue
            fi

            log "💥 Roblox tertutup sendiri (Crash Murni)! Rejoin ke Private Server..."
            sleep 2
            join_private_server
            wait_for_ingame
            start_monitor
            continue
        fi
    fi

    # JIKA PROSES BACKGROUND MONITORING MATI, DIHIDUPKAN LAGI
    if ! kill -0 "$MONITOR_PID" 2>/dev/null; then
        start_monitor
    fi

    # CEK JADWAL RELOG BERKALA
    if check_relog_needed; then
        log "🔄 Waktunya Relog berkala..."
        join_private_server
        wait_for_ingame
        start_monitor
        continue
    fi

    sleep "$CHECK_INTERVAL"
done
