#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 4.0 (FULL AUTOMATIC - FAST DETECT)
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
    local val=$1
    if [ "$val" = "1" ]; then echo "ON"; else echo "OFF"; fi
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
#    WIZARD SETUP
# ─────────────────────────────────────────

wizard_setup() {
    clr; header; echo ""
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
        clr; header; show_current_config
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
            2) clr; echo "Paste URL baru:"; read -r URL; save_config ;;
            3) menu_edit_setting ;;
            4) echo ""; echo "  Sampai jumpa!"; exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-4"; sleep 1 ;;
        esac
    done
}

menu_edit_setting() {
    while true; do
        clr; header; echo -e "\n  ── EDIT SETTING ──────────────────────\n"
        echo "  1) Relog otomatis : ${RELOG_SETIAP_JAM} jam"
        echo "  2) Restart kalau crash : $(show_toggle $RESTART_KALAU_CRASH)"
        echo "  3) Kembali ke menu utama"
        echo ""
        printf "  Pilih (1-3): "
        read -r PILIHAN
        case $PILIHAN in
            1) printf "Relog jam: "; read -r RELOG_SETIAP_JAM; save_config ;;
            2) printf "Crash (0/1): "; read -r RESTART_KALAU_CRASH; save_config ;;
            3) return ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI CORE
# ─────────────────────────────────────────

cek_apakah_terhubung() {
    if pidof "$PKG" > /dev/null 2>&1; then return 0; else return 1; fi
}

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

monitor_disconnect() {
    # Murni memantau background/foreground app saja agar logcat tidak overload
    while read -r line; do
        if echo "$line" | grep -qi "foregroundActivities=false" && echo "$line" | grep -q "$PKG"; then
            echo "1" > "$FILE_IN_BACKGROUND"
            continue
        fi
        if echo "$line" | grep -qi "foregroundActivities=true" && echo "$line" | grep -q "$PKG"; then
            echo "0" > "$FILE_IN_BACKGROUND"
            continue
        fi
    done < <(logcat -v time 2>/dev/null | grep --line-buffered -i "foregroundActivities=")
}

start_monitor() {
    kill "$MONITOR_PID" 2>/dev/null
    logcat -c
    monitor_disconnect &
    MONITOR_PID=$!
}

check_relog_needed() {
    [ "$RELOG_SETIAP_JAM" = "0" ] && return 1
    local NOW; NOW=$(date +%s)
    local LAST; LAST=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    local ELAPSED=$((NOW - LAST))
    return $(( ELAPSED < (RELOG_SETIAP_JAM * 3600) ))
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
if [ -z "$URL" ]; then wizard_setup; else menu_utama; fi

mkdir -p "$STATE_DIR"
echo "0" > "$FILE_IN_BACKGROUND"
echo "$(date +%s)" > "$FILE_LAST_RELOG"
echo "0" > "$FILE_RECONNECTING"
echo "0" > "$FILE_GRACE_UNTIL"

clr; header
log "Sistem monitoring otomatis v4.0 aktif..."
join_private_server
wait_for_ingame
start_monitor

# ─────────────────────────────────────────
#    LOOP PENGAMAT KILAT (FAST DETECT LOOP)
# ─────────────────────────────────────────
while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null || echo 0)

    # 1. JALUR UTAMA: JIKA ROBLOX TIBA-TIBA HILANG DARI MEMORI
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! pidof "$PKG" > /dev/null 2>&1; then
            
            # Cek logcat instan, apakah hilangnya karena Error / Terputus?
            if logcat -d 2>/dev/null | tail -n 50 | grep -qiE "Error code: 288|Disconnect|lost connection|shutdown|kick"; then
                log "🚨 CRASH/DC KARENA ERROR POP-UP (Terbaca Logcat)! Rejoin Instan!"
                echo "0" > "$FILE_GRACE_UNTIL"
                join_private_server
                wait_for_ingame
                start_monitor
                continue
            fi

            # Jika logcat bersih tapi sedang dalam Masa Aman Server Hop Market, biarkan lolos
            if [ "$NOW" -lt "$GRACE" ]; then
                sleep 3
                continue
            fi

            # Jika di luar masa aman dan Roblox mati tanpa alasan jelas, ini Crash Murni!
            log "💥 Roblox tertutup secara mendadak (Crash Murni). Force Rejoin!"
            join_private_server
            wait_for_ingame
            start_monitor
            continue
        fi
    fi

    # 2. JALUR BACKUP VISUAL: CEK POP-UP KONEKSI TERPUTUS PAS GAME MASIH HIDUP
    if [ "$NOW" -gt "$GRACE" ]; then
        # Jika dilayar muncul pop-up Error, Dialog, atau Disconnect
        if dumpsys window 2>/dev/null | grep -q "$PKG" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error|disconnected"; then
            sleep 3
            # Validasi sekali lagi biar gak salah eksekusi
            if dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error|disconnected"; then
                log "⚠️ Terdeteksi Pop-up Koneksi Terputus/Error di Layar! Eksekusi Rejoin!"
                join_private_server
                wait_for_ingame
                start_monitor
                continue
            fi
        fi
    fi

    # 3. FITUR AUTO DETEKSI HOPS MARKET (Tanpa Ribet Menu)
    # Jika game hidup, tapi logcat ngasih kode Delta mau pindah map/server hop
    if logcat -d 2>/dev/null | tail -n 30 | grep -qiE "Sending disconnect with reason|teleport|hop|market|trade"; then
        if [ "$NOW" -gt "$GRACE" ]; then
            log "🔄 Delta terdeteksi melakukan Server Hop ke Market! Mengunci Masa Aman..."
            echo $(( NOW + TELEPORT_GRACE )) > "$FILE_GRACE_UNTIL"
            logcat -c # Bersihkan logcat biar deteksi berikutnya presisi
        fi
    fi

    # 4. CEK RELOG OTOMATIS BERKALA
    if check_relog_needed; then
        log "🔄 Jadwal Relog tercapai. Membuka ulang Private Server..."
        join_private_server
        wait_for_ingame
        start_monitor
        continue
    fi

    sleep "$CHECK_INTERVAL"
done
