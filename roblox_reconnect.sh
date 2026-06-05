#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 4.5 (HYBRID NETWORK & GRACE FIX - ANTI BEGAL HOP)
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
header() { echo "========================================="; echo "    ROBLOX AUTO RECONNECT v4.5 (FIXED)"; echo "========================================="; }
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
        printf "  > " read -r URL
        [ -n "$URL" ] && break
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
        printf "  Pilih (1-3): " read -r PILIHAN
        case $PILIHAN in
            1) return 0 ;;
            2) echo ""; echo "Paste URL baru:"; printf "> "; read -r NEW_URL; [ -n "$NEW_URL" ] && URL="$NEW_URL" && save_config ;;
            3) exit 0 ;;
            *) echo "  ⚠ Pilih angka 1-3"; sleep 1 ;;
        esac
    done
}

# ─────────────────────────────────────────
#    FUNGSI UTAMA KONEKSI JARINGAN
# ─────────────────────────────────────────

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

cek_koneksi_game() {
    local RBX_PID; RBX_PID=$(pidof "$PKG" 2>/dev/null || ps -A 2>/dev/null | grep "$PKG" | awk '{print $2}' | head -n 1)
    if [ -z "$RBX_PID" ]; then
        echo "CRASH"
        return
    fi
    
    # Deteksi jaringan aktif (ESTABLISHED) milik Roblox di Redfinger
    local NET_CHECK; NET_CHECK=$(netstat -anp 2>/dev/null | grep "$RBX_PID" | grep -i "ESTABLISHED")
    if [ -z "$NET_CHECK" ]; then
        NET_CHECK=$(cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -v "00000000:0000" | awk '{print $4}' | grep "01")
    fi

    if [ -n "$NET_CHECK" ]; then echo "CONNECTED"; else echo "DISCONNECTED"; fi
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
    sleep 15
    echo "0" > "$FILE_RECONNECTING"
}

# Monitor sederhana hanya untuk melacak status background aplikasi
monitor_disconnect() {
    while read -r line; do
        if echo "$line" | grep -qi "foregroundActivities=false" && echo "$line" | grep -q "$PKG"; then
            echo "1" > "$FILE_IN_BACKGROUND"
            log "📱 App masuk background"
        elif echo "$line" | grep -qi "foregroundActivities=true" && echo "$line" | grep -q "$PKG"; then
            echo "0" > "$FILE_IN_BACKGROUND"
            log "📱 App kembali foreground"
        fi
    done < <(logcat -v time 2>/dev/null | grep --line-buffered -i "foregroundActivities=")
}

start_monitor() {
    kill "$MONITOR_PID" 2>/dev/null
    sleep 1
    logcat -c
    monitor_disconnect &
    MONITOR_PID=$!
}

check_relog_needed() {
    [ "$RELOG_SETIAP_JAM" = "0" ] && return 1
    local NOW; NOW=$(date +%s)
    local LAST; LAST=$(cat "$FILE_LAST_RELOG" 2>/dev/null || echo "$NOW")
    [ $((NOW - LAST)) -ge $((RELOG_SETIAP_JAM * 3600)) ]
}

cleanup() { log "🛑 Script dihentikan."; kill "$MONITOR_PID" 2>/dev/null; rm -rf "$STATE_DIR"; exit 0; }
trap cleanup INT TERM

# ─────────────────────────────────────────
#    MAIN PROGRAM EXECUTION
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
start_monitor

while true; do
    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
    BG_STATE=$(cat "$FILE_IN_BACKGROUND" 2>/dev/null)
    
    STATUS_GAME=$(cek_koneksi_game)

    # 1. CEK CRASH
    if [ "$STATUS_GAME" = "CRASH" ] && [ "$RESTART_KALAU_CRASH" = "1" ]; then
        log "💥 Roblox crash/tertutup! Restart balik ke Private Server..."
        join_private_server
        wait_for_ingame
        start_monitor
        continue
    fi

    # Lepaskan pengecekan jika app sedang di-home (kecuali fiturnya dinyalakan)
    if [ "$BG_STATE" = "1" ] && [ "$RECONNECT_SAAT_HOME" = "0" ]; then
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # 2. DETEKSI AMAN ERROR 288 (HANYA AKTIF JIKA GRACE PERIOD SUDAH HABIS)
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        if [ "$STATUS_GAME" = "DISCONNECTED" ] && [ "$RECONNECT_OTOMATIS" = "1" ]; then
            
            # Beri toleransi 15 detik untuk membedakan antara lag biasa / loading map, dengan DC beneran
            log "🔍 Deteksi awal: Kehilangan internet game. Verifikasi dalam 15 detik..."
            sleep 15
            
            if [ "$(cek_koneksi_game)" = "DISCONNECTED" ]; then
                log "🚨 POSITIF: Terbengong di pop-up Koneksi Terputus (Error 288)!"
                log "♻️ Force close Roblox dan giring balik ke Private Server Garden..."
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
        log "✅ Roblox running & Terkoneksi Aman."
        LAST_VERBOSE=$NOW
    fi

    sleep "$CHECK_INTERVAL"
done
