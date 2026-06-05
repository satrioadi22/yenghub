#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 5.0 (LOG ACTIVITY TRACKER - REDFINGER SPECIAL)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=10
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"
CONFIG_FILE="$HOME/roblox_config.cfg"

STATE_DIR="/data/local/tmp/rbx_state"
FILE_IN_BACKGROUND="$STATE_DIR/in_background"
FILE_LAST_RELOG="$STATE_DIR/last_relog"
FILE_RECONNECTING="$STATE_DIR/reconnecting"
FILE_GRACE_UNTIL="$STATE_DIR/grace_until"

# Folder log internal bawaan aplikasi Roblox
RBX_LOG_DIR="/sdcard/Android/data/com.roblox.client/files/logs"

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
RECONNECT_SAAT_HOME=$RECONNECT_SAAT_HOME
EOF
}

default_config() { URL=""; RELOG_SETIAP_JAM=1; RECONNECT_OTOMATIS=1; RESTART_KALAU_CRASH=1; RECONNECT_SAAT_HOME=0; }
clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }
header() { echo "========================================="; echo "    ROBLOX AUTO RECONNECT v5.0 (LIVE)"; echo "========================================="; }
show_toggle() { if [ "$1" = "1" ]; then echo "ON"; else echo "OFF"; fi; }

show_current_config() {
    echo ""
    echo "  URL    : ${URL:-[belum diisi]}"
    echo "  Relog  : ${RELOG_SETIAP_JAM} jam"
    echo "  Reconnect otomatis : $(show_toggle $RECONNECT_OTOMATIS)"
    echo "  Restart kalau crash: $(show_toggle $RESTART_KALAU_CRASH)"
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
            2) echo ""; echo "Paste URL baru:"; printf "> "; read -r NEW_URL; [ -n "$NEW_URL" ] && URL="$NEW_URL" && save_config ;;
            3) exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-3"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    CORE LOGIC: TRACKING AKTIVITAS FILE
# ─────────────────────────────────────────

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

cek_status_aktif_game() {
    # 1. Cek apakah proses aplikasi Roblox terdeteksi hidup di sistem
    if ! pidof "$PKG" > /dev/null 2>&1 && ! ps -A 2>/dev/null | grep -q "$PKG"; then
        echo "CRASH"
        return
    fi

    # 2. Cari file log Roblox yang paling baru dimodifikasi
    local LATEST_LOG; LATEST_LOG=$(ls -t "$RBX_LOG_DIR"/*.log 2>/dev/null | head -n 1)
    if [ -z "$LATEST_LOG" ]; then
        # Jika folder log belum terbaca, bypass agar tidak salah eksekusi
        echo "ACTIVE"
        return
    fi

    # Ambil waktu modifikasi terakhir file tersebut (dalam hitungan detik epoch linux)
    local LAST_MOD; LAST_MOD=$(stat -c %Y "$LATEST_LOG" 2>/dev/null)
    if [ -z "$LAST_MOD" ]; then
        echo "ACTIVE"
        return
    fi

    local NOW; NOW=$(date +%s)
    local IDLE_TIME=$((NOW - LAST_MOD))

    # Jika file log tidak diperbarui/ditulis sama sekali selama lebih dari 25 detik
    if [ "$IDLE_TIME" -gt 25 ]; then
        echo "STUCK"
    else
        echo "ACTIVE"
    fi
}

join_private_server() {
    log ""
    log "🚀 Join private server Grow a Garden..."
    echo "1" > "$FILE_RECONNECTING"
    
    # Amankan waktu 180 detik (3 Menit). Selama masa ini, HOP DELTA TIDAK AKAN DIGANGGU.
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

check_relog_needed() {
    [ "$RELOG_SETIAP_JAM" = "0" ] && return 1
    local NOW; NOW=$(date +%s)
    local LAST; LAST=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    [ $((NOW - LAST)) -ge $((RELOG_SETIAP_JAM * 3600)) ]
}

# ─────────────────────────────────────────
#    MAIN PROGRAM RUNNER
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then echo "⚠️ Minta akses root..."; exec su -c "$0"; fi

default_config; load_config
if [ -z "$URL" ]; then wizard_setup; else menu_utama; fi

mkdir -p "$STATE_DIR"
echo "0" > "$FILE_IN_BACKGROUND"
echo "0" > "$FILE_RECONNECTING"

clr
header
log "URL: $URL"
echo "========================================="

join_private_server
wait_for_ingame

while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
    
    STATUS_GAME=$(cek_status_aktif_game)

    # 1. HANDLE CRASH / PROSES MATI
    if [ "$STATUS_GAME" = "CRASH" ] && [ "$RESTART_KALAU_CRASH" = "1" ]; then
        log "💥 Roblox tertutup/crash! Mengembalikan ke Private Server..."
        join_private_server
        wait_for_ingame
        continue
    fi

    # 2. HANDLE ERROR 288 / STUCK DI LAYAR KONEKSI TERPUTUS
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        if [ "$STATUS_GAME" = "STUCK" ] && [ "$RECONNECT_OTOMATIS" = "1" ]; then
            log "🔍 Deteksi awal: Log Roblox berhenti merespons (Indikasi DC). Menunggu verifikasi akhir..."
            sleep 10
            
            # Cek ulang satu kali lagi untuk memastikan bukan karena lag spike parah
            if [ "$(cek_status_aktif_game)" = "STUCK" ]; then
                log "🚨 POSITIF: Game membeku di pop-up Terputus (Error 288)!"
                log "♻️ Melakukan Force Close & Rejoin otomatis ke Private Server..."
                join_private_server
                wait_for_ingame
                continue
            fi
        fi
    fi

    if check_relog_needed; then
        log "🔄 Relog otomatis berkala..."
        join_private_server
        wait_for_ingame
        continue
    fi

    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Roblox running & Aktif mengirim data."
        LAST_VERBOSE=$NOW
    fi

    sleep "$CHECK_INTERVAL"
done
