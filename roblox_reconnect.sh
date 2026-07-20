#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT - MARKET DIRECT
#    Versi: 5.0 (Direct Market Link, no Hop/PS)
#
#    CHANGELOG v5.0:
#    - Dihapus: semua logic hop/teleport (Hydra/TeleportService)
#      karena URL sekarang langsung masuk ke Market
#      (privateServerLinkCode), jadi tidak ada perpindahan
#      dari Private Server -> Market lagi.
#    - Dihapus: PAUSE khusus "sebelum pindah ke Market Trade"
#      (fitur pause manual tetap ada, tapi general-purpose,
#      bukan lagi terikat ke proses hop)
#    - Ditambah: deteksi popup "Koneksi Terputus" untuk
#      SEMUA kode eror (285, 288, dst) - bukan cuma 288
#    - Disederhanakan: satu jalur reconnect untuk semua jenis DC
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
FILE_PAUSE_UNTIL="$STATE_DIR/pause_until"

RECONNECT_COOLDOWN=45
TELEPORT_GRACE=180        # detik — abaikan DC signal sesaat setelah kita baru join
DC_CONFIRM_DELAY=5        # detik — delay kecil sebelum eksekusi rejoin (anti double-trigger)
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
#    CONFIG ROBLOX AUTO RECONNECT (MARKET)
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
#    FUNGSI PAUSE RECONNECT (manual, general-purpose)
# ─────────────────────────────────────────

is_paused() {
    mkdir -p "$STATE_DIR"
    local NOW; NOW=$(date +%s)
    local PAUSE; PAUSE=$(cat "$FILE_PAUSE_UNTIL" 2>/dev/null)
    if [ -n "$PAUSE" ] && [ "$NOW" -lt "$PAUSE" ]; then
        return 0
    fi
    return 1
}

set_pause() {
    local MENIT=$1
    local SAMPAI=$(( $(date +%s) + MENIT * 60 ))
    mkdir -p "$STATE_DIR"
    echo "$SAMPAI" > "$FILE_PAUSE_UNTIL"
    log "⏸️  PAUSE RECONNECT aktif selama ${MENIT} menit (sampai $(date -d @$SAMPAI '+%H:%M:%S' 2>/dev/null || date -r $SAMPAI '+%H:%M:%S' 2>/dev/null || echo 'selesai'))"
}

sisa_pause() {
    local NOW; NOW=$(date +%s)
    local PAUSE; PAUSE=$(cat "$FILE_PAUSE_UNTIL" 2>/dev/null)
    if [ -n "$PAUSE" ] && [ "$NOW" -lt "$PAUSE" ]; then
        echo $(( PAUSE - NOW ))
    else
        echo 0
    fi
}

# ─────────────────────────────────────────
#    FUNGSI TAMPILAN
# ─────────────────────────────────────────

clr() { clear 2>/dev/null || printf '\033[2J\033[H'; }

header() {
    echo "========================================="
    echo "    ROBLOX AUTO RECONNECT - MARKET DIRECT"
    echo "    Versi 5.0"
    echo "========================================="
}

show_toggle() {
    local val=$1
    if [ "$val" = "1" ]; then echo "ON"; else echo "OFF"; fi
}

show_current_config() {
    echo ""
    echo "  URL (Market) : ${URL:-[belum diisi]}"
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
        echo "  Paste link Market kamu"
        echo "  (contoh: https://www.roblox.com/id/games/129954712878723/Grow-a-Garden?privateServerLinkCode=...):"
        printf "  > "
        read -r URL
        if [ -n "$URL" ]; then
            break
        fi
        echo "  ⚠ URL tidak boleh kosong!"
        echo ""
    done

    echo ""
    echo "  Relog otomatis setiap berapa jam?"
    echo "  (ketik 0 untuk mematikan relog otomatis, default: 1)"
    printf "  > "
    read -r INPUT_RELOG
    if [[ "$INPUT_RELOG" =~ ^[0-9]+$ ]]; then
        RELOG_SETIAP_JAM=$INPUT_RELOG
    else
        RELOG_SETIAP_JAM=1
    fi

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
    echo ""
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

        SISA=$(sisa_pause)
        if [ "$SISA" -gt 0 ]; then
            echo "  ⏸️  PAUSE AKTIF — sisa ${SISA} detik"
            echo ""
        fi

        echo "  Mau ngapain?"
        echo ""
        echo "  1) Langsung jalanin"
        echo "  2) Ganti URL Market"
        echo "  3) Ubah setting (relog, reconnect, dll)"
        echo "  4) ⏸️  Pause reconnect (misal mau isi form/trading manual)"
        echo "  5) Keluar"
        echo ""
        printf "  Pilih (1-5): "
        read -r PILIHAN

        case $PILIHAN in
            1) return 0 ;;
            2) menu_ganti_url ;;
            3) menu_edit_setting ;;
            4) menu_pause ;;
            5) echo ""; echo "  Sampai jumpa!"; echo ""; exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-5"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    MENU PAUSE
# ─────────────────────────────────────────

menu_pause() {
    clr
    header
    echo ""
    echo "  ══════════════════════════════════════"
    echo "  ⏸️   PAUSE RECONNECT"
    echo "  ══════════════════════════════════════"
    echo ""
    echo "  Pakai ini kalau kamu mau interaksi manual"
    echo "  (isi form, dll) tanpa risiko script salah"
    echo "  nangkep itu sebagai disconnect."
    echo ""
    echo "  Berapa menit mau di-pause?"
    echo "  (contoh: 15 untuk 15 menit, 0 untuk batalkan pause)"
    printf "  > "
    read -r MENIT

    if [[ "$MENIT" =~ ^[0-9]+$ ]]; then
        if [ "$MENIT" = "0" ]; then
            echo "0" > "$FILE_PAUSE_UNTIL"
            echo ""
            echo "  ✅ Pause dibatalkan! Reconnect kembali aktif."
        else
            set_pause "$MENIT"
            echo ""
            echo "  ✅ Pause aktif selama ${MENIT} menit!"
        fi
    else
        echo ""
        echo "  ⚠ Masukkan angka!"
    fi
    sleep 2
}

menu_ganti_url() {
    clr
    header
    echo ""
    echo "  URL saat ini:"
    echo "  ${URL:-[kosong]}"
    echo ""
    echo "  Paste URL Market baru (Enter untuk batal):"
    printf "  > "
    read -r NEW_URL
    if [ -n "$NEW_URL" ]; then
        URL="$NEW_URL"
        save_config
        echo ""
        echo "  ✅ URL diperbarui!"
    else
        echo ""
        echo "  Dibatalkan."
    fi
    sleep 1
}

menu_edit_setting() {
    while true; do
        clr
        header
        echo ""
        echo "  ── EDIT SETTING ──────────────────────"
        echo ""
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
                echo ""
                echo "  Relog setiap berapa jam? (0 = matikan relog):"
                printf "  > "
                read -r V
                if [[ "$V" =~ ^[0-9]+$ ]]; then
                    RELOG_SETIAP_JAM=$V
                    save_config
                    echo "  ✅ Disimpan!"
                else
                    echo "  ⚠ Masukkan angka!"
                fi
                sleep 1
                ;;
            2)
                echo ""
                echo "  Reconnect otomatis (1=ON / 0=OFF):"
                printf "  > "
                read -r V
                if [ "$V" = "0" ] || [ "$V" = "1" ]; then
                    RECONNECT_OTOMATIS=$V
                    save_config
                    echo "  ✅ Disimpan!"
                else
                    echo "  ⚠ Masukkan 0 atau 1!"
                fi
                sleep 1
                ;;
            3)
                echo ""
                echo "  Restart kalau crash (1=ON / 0=OFF):"
                printf "  > "
                read -r V
                if [ "$V" = "0" ] || [ "$V" = "1" ]; then
                    RESTART_KALAU_CRASH=$V
                    save_config
                    echo "  ✅ Disimpan!"
                else
                    echo "  ⚠ Masukkan 0 atau 1!"
                fi
                sleep 1
                ;;
            4)
                echo ""
                echo "  Reconnect saat home (1=ON / 0=OFF):"
                printf "  > "
                read -r V
                if [ "$V" = "0" ] || [ "$V" = "1" ]; then
                    RECONNECT_SAAT_HOME=$V
                    save_config
                    echo "  ✅ Disimpan!"
                else
                    echo "  ⚠ Masukkan 0 atau 1!"
                fi
                sleep 1
                ;;
            5) return ;;
            *) echo "  ⚠ Pilih 1-5"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI CORE (log, join, monitor)
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

join_market() {
    log ""
    log "🚀 Join ke Market..."

    echo "1" > "$FILE_RECONNECTING"
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"

    log "✅ Market launched"
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

# Jalankan rejoin dengan semua guard (cooldown, sudah reconnecting, dsb)
eksekusi_rejoin() {
    local ALASAN="$1"

    if is_paused; then
        SISA=$(sisa_pause)
        log "⏸️ DC terdeteksi ($ALASAN) tapi PAUSE aktif (sisa ${SISA}s) — skip reconnect."
        return
    fi

    if [ "$RECONNECT_OTOMATIS" != "1" ]; then
        return
    fi

    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
    if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then
        return
    fi

    RECONNECTING=$(cat "$FILE_RECONNECTING" 2>/dev/null)
    [ "$RECONNECTING" = "1" ] && return

    log "🚨 Koneksi Terputus terdeteksi ($ALASAN) — Auto Rejoin ke Market!"
    echo "$NOW" > "$FILE_LAST_RECONNECT"
    sleep "$DC_CONFIRM_DELAY"
    join_market
    wait_for_ingame
}

monitor_disconnect() {
    log "🔍 Monitor DC aktif (PID: $$)"
    echo "0" > "$FILE_IN_BACKGROUND"

    while read -r line; do

        # ── DETEKSI FOREGROUND / BACKGROUND ──
        if echo "$line" | grep -qi "foregroundActivities=false" && echo "$line" | grep -q "com.roblox.client"; then
            echo "1" > "$FILE_IN_BACKGROUND"
            log "📱 App masuk background"
            continue
        fi

        if echo "$line" | grep -qi "foregroundActivities=true" && echo "$line" | grep -q "com.roblox.client"; then
            sleep 5
            echo "0" > "$FILE_IN_BACKGROUND"
            log "📱 App kembali foreground"
            continue
        fi

        # ── DETEKSI DISCONNECT (semua kode eror: 285, 288, dll) ──
        DC_DETECTED=0
        DC_REASON=""

        if echo "$line" | grep -qiE "Client:Disconnect|NetworkClient:Remove|MegaReplicatorLogDisconnectCleanUpLog|sendAnalyticsBeforeLeave|Connection refused|shutdown|kick"; then
            DC_DETECTED=1
            KODE=$(echo "$line" | grep -oE "[0-9]{3}" | head -1)
            DC_REASON="Disconnect signal${KODE:+ (kode: $KODE)}"
        fi

        if echo "$line" | grep -qiE "Error code: [0-9]+|Disconnect error: [0-9]+"; then
            DC_DETECTED=1
            KODE=$(echo "$line" | grep -oE "[0-9]{3}" | head -1)
            DC_REASON="Error code${KODE:+ $KODE}"
        fi

        if echo "$line" | grep -qi "Sending disconnect with reason"; then
            DC_DETECTED=1
            DC_REASON="Sending disconnect"
        fi

        if echo "$line" | grep -qi "Lost connection with reason"; then
            DC_DETECTED=1
            DC_REASON="Lost connection"
        fi

        if echo "$line" | grep -qi "Disconnected from server for reason"; then
            DC_DETECTED=1
            DC_REASON="Disconnected from server"
        fi

        if [ "$DC_DETECTED" -eq 1 ]; then
            eksekusi_rejoin "$DC_REASON"
            continue
        fi

    done < <(logcat -v time 2>/dev/null | grep --line-buffered -iE \
        "Client:Disconnect|NetworkClient:Remove|MegaReplicatorLogDisconnectCleanUpLog|sendAnalyticsBeforeLeave|Connection refused|Sending disconnect with reason|Lost connection with reason|Disconnected from server for reason|foregroundActivities=|Error code: [0-9]|Disconnect error: [0-9]|shutdown|kick")
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
    local LAST; LAST=$(cat "$FILE_LAST_RELOG")
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
echo "0" > "$FILE_PAUSE_UNTIL"

clr
echo "=========================================" | tee -a "$LOG_FILE"
echo "    ROBLOX AUTO RECONNECT - MARKET DIRECT" | tee -a "$LOG_FILE"
echo "    Versi 5.0"                              | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
log "URL (Market)     : $URL"
log "Relog            : setiap ${RELOG_SETIAP_JAM} jam    → $([ "$RELOG_SETIAP_JAM" = "0" ] && echo OFF || echo ON)"
log "Reconnect        : DC detection  → $(show_toggle $RECONNECT_OTOMATIS)"
log "Restart crash    : auto restart  → $(show_toggle $RESTART_KALAU_CRASH)"
log "Reconnect@home   : saat home     → $(show_toggle $RECONNECT_SAAT_HOME)"
log "Confirm delay    : ${DC_CONFIRM_DELAY} detik sebelum eksekusi rejoin"
log "Log file         : $LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo ""

join_market
wait_for_ingame

log "🔍 Monitoring aktif..."
echo "-----------------------------------------" | tee -a "$LOG_FILE"

start_monitor

while true; do

    NOW=$(date +%s)

    # ── CEK PAUSE MANUAL DI MAIN LOOP ──
    if is_paused; then
        SISA=$(sisa_pause)
        if [ $((NOW - LAST_VERBOSE)) -ge 60 ]; then
            log "⏸️ PAUSE aktif — sisa ${SISA}s — reconnect ditahan"
            LAST_VERBOSE=$NOW
        fi
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # ── CEK CRASH BIASA ──
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
            log "💥 Roblox crash / tertutup! Restart..."
            sleep 3
            join_market
            wait_for_ingame
            start_monitor
            continue
        fi
    fi

    if check_relog_needed; then
        log "🔄 Relog setiap ${RELOG_SETIAP_JAM} jam..."
        join_market
        wait_for_ingame
        start_monitor
        continue
    fi

    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Roblox running di Market"
        LAST_VERBOSE=$NOW
    fi

    sleep "$CHECK_INTERVAL"
done
