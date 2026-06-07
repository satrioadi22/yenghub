#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 3.7 (+ Auto Pause 3 menit saat deteksi Market Trade Hop)
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
FILE_PAUSE_UNTIL="$STATE_DIR/pause_until"   # <-- BARU: file pause manual

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
#    FUNGSI PAUSE RECONNECT (BARU)
# ─────────────────────────────────────────

is_paused() {
    mkdir -p "$STATE_DIR"
    local NOW; NOW=$(date +%s)
    local PAUSE; PAUSE=$(cat "$FILE_PAUSE_UNTIL" 2>/dev/null)
    if [ -n "$PAUSE" ] && [ "$NOW" -lt "$PAUSE" ]; then
        return 0   # masih dalam mode pause
    fi
    return 1       # tidak pause
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
    echo "    ROBLOX AUTO RECONNECT + AUTO RELOG"
    echo "    Versi 3.7 (+ Auto Pause Market Trade)"
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

        # Tampilkan status pause kalau aktif
        SISA=$(sisa_pause)
        if [ "$SISA" -gt 0 ]; then
            echo "  ⏸️  PAUSE AKTIF — sisa ${SISA} detik"
            echo ""
        fi

        echo "  Mau ngapain?"
        echo ""
        echo "  1) Langsung jalanin"
        echo "  2) Ganti URL private server"
        echo "  3) Ubah setting (relog, reconnect, dll)"
        echo "  4) ⏸️  Pause reconnect (buat pindah ke Market Trade)"
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
#    MENU PAUSE (BARU)
# ─────────────────────────────────────────

menu_pause() {
    clr
    header
    echo ""
    echo "  ══════════════════════════════════════"
    echo "  ⏸️   PAUSE RECONNECT"
    echo "  ══════════════════════════════════════"
    echo ""
    echo "  Gunakan ini sebelum kamu pindah ke"
    echo "  Market Trade agar script tidak"
    echo "  langsung rejoin ke private server."
    echo ""
    echo "  Berapa menit mau di-pause?"
    echo "  (contoh: 5 untuk 5 menit, 0 untuk batalkan pause)"
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
            echo "  Sekarang kamu aman pindah ke Market Trade."
            echo "  Setelah selesai, reconnect otomatis kembali aktif."
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
    echo "  Paste URL baru (Enter untuk batal):"
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

        # ── CEK PAUSE DULU SEBELUM PROSES APAPUN ──
        if is_paused; then
            SISA=$(sisa_pause)
            # Log setiap 30 detik supaya tidak spam
            continue
        fi

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

        # ── CEK HOP/TELEPORT DULUAN SEBELUM APAPUN ──
        if echo "$line" | grep -qiE "teleport|TeleportService|ServerHop|server hop|ChangingServers|doTeleport|finishTeleportWithJoinScriptPayload|SessionTransitionFSM.*Teleported|HydraHub|Hydra.*Loaded"; then
            log "🔄 Deteksi Hop (Hydra/Delta) — Auto PAUSE 3 menit!"
            set_pause 3
            continue
        fi

        DC_DETECTED=0
        DC_REASON=""

        # Deteksi Error 288 — pakai keyword ASLI dari logcat
        if echo "$line" | grep -qiE "Client:Disconnect|NetworkClient:Remove|MegaReplicatorLogDisconnectCleanUpLog|sendAnalyticsBeforeLeave|Connection refused|Error code: 288|Disconnect error: 288|shutdown|kick"; then
            DC_DETECTED=1
            DC_REASON="Error288"
        fi

        if echo "$line" | grep -qi "Sending disconnect with reason"; then
            DC_DETECTED=1
            DC_REASON="Sending disconnect (Logcat Client)"
        fi

        if echo "$line" | grep -qi "Lost connection with reason"; then
            DC_DETECTED=1; DC_REASON="Lost connection with reason"
        fi
        if echo "$line" | grep -qi "Disconnected from server for reason"; then
            DC_DETECTED=1; DC_REASON="Disconnected from server"
        fi

        if [ "$DC_DETECTED" -eq 1 ]; then

            # Error 288 = bypass pause, langsung rejoin
            if [ "$DC_REASON" = "Error288" ] || [ "$DC_REASON" = "Lost connection with reason" ]; then
                log "🚨 Koneksi Terputus (Error 288) — Force Rejoin ke Private Server!"
                echo "0" > "$FILE_PAUSE_UNTIL"
                echo "0" > "$FILE_RECONNECTING"
                join_private_server
                wait_for_ingame
                continue
            fi

            # DC biasa — cek pause dulu
            if is_paused; then
                SISA=$(sisa_pause)
                log "⏸️ DC terdeteksi ($DC_REASON) tapi PAUSE aktif (sisa ${SISA}s) — skip reconnect."
                continue
            fi

            if [ "$RECONNECT_OTOMATIS" = "1" ]; then
                WAIT_TIME=45
                log "⚠️ Deteksi DC biasa ($DC_REASON). Menunggu $WAIT_TIME detik..."
                sleep $WAIT_TIME

                if is_paused; then
                    log "⏸️ PAUSE aktif setelah tunggu — skip reconnect."
                    continue
                fi

                if cek_apakah_terhubung; then
                    log "✅ Game normal / Hop Delta sukses. Skip Reconnect."
                    DC_DETECTED=0
                    continue
                fi
            else
                continue
            fi

            log "❌ Tetap Terputus. Mengembalikan ke Private Server..."

            NOW=$(date +%s)
            GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)
            if [ -n "$GRACE" ] && [ "$NOW" -lt "$GRACE" ]; then continue; fi
            RECONNECTING=$(cat "$FILE_RECONNECTING")
            [ "$RECONNECTING" = "1" ] && continue

            log "❌ Eksekusi Rejoin Utama!"
            echo "$NOW" > "$FILE_LAST_RECONNECT"
            sleep 5
            join_private_server
            wait_for_ingame
        fi

    done < <(logcat -v time 2>/dev/null | grep --line-buffered -iE \
        "Client:Disconnect|NetworkClient:Remove|MegaReplicatorLogDisconnectCleanUpLog|sendAnalyticsBeforeLeave|Connection refused|Sending disconnect with reason|Lost connection with reason|Disconnected from server for reason|foregroundActivities=|288|shutdown|kick|teleport|TeleportService|ServerHop|server hop|ChangingServers|doTeleport|finishTeleportWithJoinScriptPayload|SessionTransitionFSM|HydraHub|Hydra.*Loaded")
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
echo "    ROBLOX AUTO RECONNECT + AUTO RELOG"    | tee -a "$LOG_FILE"
echo "    Versi 3.7 (+ Auto Pause Market Trade)"   | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
log "URL              : $URL"
log "Relog            : setiap ${RELOG_SETIAP_JAM} jam    → $([ "$RELOG_SETIAP_JAM" = "0" ] && echo OFF || echo ON)"
log "Reconnect        : DC detection  → $(show_toggle $RECONNECT_OTOMATIS)"
log "Restart crash    : auto restart  → $(show_toggle $RESTART_KALAU_CRASH)"
log "Reconnect@home   : saat home     → $(show_toggle $RECONNECT_SAAT_HOME)"
log "Log file         : $LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo ""
echo "  💡 TIP: Sebelum pindah ke Market Trade,"
echo "     buka sesi Termux baru dan ketik:"
echo "     echo \$(( \$(date +%s) + 300 )) > /data/local/tmp/rbx_state/pause_until"
echo "     (pause 5 menit)"
echo ""

join_private_server
wait_for_ingame

log "🔍 Monitoring aktif..."
echo "-----------------------------------------" | tee -a "$LOG_FILE"

start_monitor

while true; do

    NOW=$(date +%s)
    GRACE=$(cat "$FILE_GRACE_UNTIL" 2>/dev/null)

    # ── CEK POPUP ERROR 288 — SELALU JALAN MESKIPUN PAUSE AKTIF ──
    # Harus dicek paling duluan, karena popup 288 bisa muncul kapanpun
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        if dumpsys window 2>/dev/null | grep -q "com.roblox.client" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error"; then
            sleep 5
            if dumpsys window 2>/dev/null | grep -q "com.roblox.client" && dumpsys window 2>/dev/null | grep -qiE "popup|dialog|error"; then
                log "⚠️ Pop-up Error 288 terdeteksi! Batalkan pause & Force Rejoin ke Private Server!"
                echo "0" > "$FILE_PAUSE_UNTIL"
                am force-stop "$PKG"
                sleep 3
                join_private_server
                wait_for_ingame
                start_monitor
                continue
            fi
        fi
    fi

    # ── CEK PAUSE DI MAIN LOOP ──
    if is_paused; then
        # Roblox masih jalan = masih di Market Trade, perpanjang pause otomatis
        if ps -A 2>/dev/null | grep -q "$PKG" || pidof "$PKG" > /dev/null 2>&1; then
            NEW_PAUSE=$(( $(date +%s) + 30 ))
            echo "$NEW_PAUSE" > "$FILE_PAUSE_UNTIL"
            if [ $((NOW - LAST_VERBOSE)) -ge 60 ]; then
                log "⏸️ PAUSE aktif — Roblox masih jalan di Market Trade — reconnect ditahan"
                LAST_VERBOSE=$NOW
            fi
        else
            # Roblox tutup saat pause aktif
            # Tunggu dulu 20 detik — mungkin Hydra lagi restart Roblox untuk hop
            log "⚠️ Roblox tutup saat PAUSE aktif — tunggu 20 detik dulu (mungkin Hydra hop)..."
            sleep 20

            # Cek lagi setelah tunggu
            if ps -A 2>/dev/null | grep -q "$PKG" || pidof "$PKG" > /dev/null 2>&1; then
                # Roblox hidup lagi = Hydra berhasil hop, perpanjang pause
                log "✅ Roblox hidup lagi — Hydra hop sukses, pause diperpanjang."
                NEW_PAUSE=$(( $(date +%s) + 30 ))
                echo "$NEW_PAUSE" > "$FILE_PAUSE_UNTIL"
            else
                # Roblox beneran tutup = rejoin ke private server
                log "💥 Roblox beneran tutup saat di Market Trade — Rejoin ke Private Server..."
                echo "0" > "$FILE_PAUSE_UNTIL"
                sleep 3
                join_private_server
                wait_for_ingame
                start_monitor
            fi
        fi

        sleep "$CHECK_INTERVAL"
        continue
    fi

    # ── CEK CRASH BIASA (hanya saat tidak pause) ──
    if [ "$RESTART_KALAU_CRASH" = "1" ]; then
        if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
            log "💥 Roblox crash! Restart..."
            sleep 3
            join_private_server
            wait_for_ingame
            start_monitor
            continue
        fi
    fi

    if check_relog_needed; then
        # Jangan relog kalau lagi pause (mungkin lagi di Market Trade)
        if is_paused; then
            log "⏸️ Waktunya relog tapi PAUSE aktif — skip relog."
            sleep "$CHECK_INTERVAL"
            continue
        fi
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
