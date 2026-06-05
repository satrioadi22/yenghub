#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 6.0 (UI AUTOMATOR TEXT SCANNER)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=12
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

STATE_DIR="/data/local/tmp/rbx_state"
FILE_LAST_RELOG="$STATE_DIR/last_relog"
FILE_GRACE_UNTIL="$STATE_DIR/grace_until"

TELEPORT_GRACE=180
LAST_VERBOSE=0
VERBOSE_INTERVAL=600

# ─────────────────────────────────────────
#    FUNGSI CONFIG & TAMPILAN
# ─────────────────────────────────────────

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
save_config() {
    cat > "$CONFIG_FILE" <<EOF
URL="$URL"
RELOG_SETIAP_JAM=$RELOG_SETIAP_JAM
RECONNECT_OTOMATIS=$RECONNECT_OTOMATIS
RESTART_KALAU_CRASH=$RESTART_KALAU_CRASH
EOF
}

default_config() { URL=""; RELOG_SETIAP_JAM=1; RECONNECT_OTOMATIS=1; RESTART_KALAU_CRASH=1; }
clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }
header() { echo "========================================="; echo "    ROBLOX AUTO RECONNECT v6.0 (SCANNER)"; echo "========================================="; }

show_current_config() {
    echo ""
    echo "  URL    : ${URL:-[belum diisi]}"
    echo "  Relog  : ${RELOG_SETIAP_JAM} jam"
    echo "  Reconnect Otomatis : ON"
    echo "  Restart Kalau Crash: ON"
    echo ""
}

wizard_setup() {
    clr; header; echo ""
    while true; do
        echo "  Paste link private server Roblox kamu:"
        printf "  > "
        read -r URL
        if [ -n "$URL" ]; then break; fi
        echo "  ⚠ URL tidak boleh kosong!"; echo ""
    done
    RELOG_SETIAP_JAM=1; RECONNECT_OTOMATIS=1; RESTART_KALAU_CRASH=1
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
            2) echo ""; echo "Paste URL baru:"; printf "> "; read -r NEW_URL; [ -n "$NEW_URL" ] && URL="$NEW_URL" && save_config ;;
            3) exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-3"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI UTAMA ENGINE
# ─────────────────────────────────────────

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

join_private_server() {
    log ""
    log "🚀 Join private server Grow a Garden..."
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Private server launched"
    echo "$(date +%s)" > "$FILE_LAST_RELOG"
}

wait_for_ingame() {
    log "👀 Menunggu proses loading awal (25 detik)..."
    sleep 25
}

check_relog_needed() {
    [ "$RELOG_SETIAP_JAM" = "0" ] && return 1
    local NOW; NOW=$(date +%s)
    local LAST; LAST=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    [ $((NOW - LAST)) -ge $((RELOG_SETIAP_JAM * 3600)) ]
}

# ─────────────────────────────────────────
#    MAIN RUNNER
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then echo "⚠️ Minta akses root..."; exec su -c "$0"; fi

default_config; load_config
if [ -z "$URL" ]; then wizard_setup; else menu_utama; fi

mkdir -p "$STATE_DIR"
clr; header
log "URL: $URL"
echo "========================================="

join_private_server
wait_for_ingame

while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)

    # 1. CEK CRASH (APLIKASI MATI)
    if ! pidof "$PKG" > /dev/null 2>&1 && ! ps -A 2>/dev/null | grep -q "$PKG"; then
        log "💥 Roblox tertutup/crash! Kembalikan ke Private Server..."
        join_private_server
        wait_for_ingame
        continue
    fi

    # 2. CEK POP-UP ERROR 288 DENGAN SCAN TEXT LAYAR (Hanya jalan di luar masa aman)
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        
        # Dump susunan text yang ada di layar saat ini ke file sementara
        UI_DUMP="/data/local/tmp/window_dump.xml"
        rm -f "$UI_DUMP"
        
        # Mengambil data text layar via uiautomator Android
        uiautomator dump "$UI_DUMP" >/dev/null 2>&1
        
        if [ -f "$UI_DUMP" ]; then
            # Scan apakah ada text "Koneksi Terputus", "Terputus", atau kode "288" di layar Redfinger
            if grep -qiE "Koneksi Terputus|Terputus|288|Hubungkan Kembali" "$UI_DUMP"; then
                log "🚨 SCAN MATCH: Terdeteksi tulisan 'Koneksi Terputus / 288' terpampang di layar!"
                log "♻️ Melakukan Rejoin otomatis ke Private Server..."
                rm -f "$UI_DUMP"
                join_private_server
                wait_for_ingame
                continue
            fi
            rm -f "$UI_DUMP"
        fi
    fi

    # 3. CEK TIMER RELOG
    if check_relog_needed; then
        log "🔄 Relog berkala setiap $RELOG_SETIAP_JAM jam..."
        join_private_server
        wait_for_ingame
        continue
    fi

    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Roblox running aman (Layar Bersih dari Pop-up)."
        LAST_VERBOSE=$NOW
    fi

    sleep "$CHECK_INTERVAL"
done
