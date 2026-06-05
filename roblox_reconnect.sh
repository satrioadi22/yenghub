#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 8.0 (ROBLOX LOG MONITOR - ANTI BLUNDER)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=10
CONFIG_FILE="$HOME/roblox_config.cfg"
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"

TELEPORT_GRACE=180
LAST_VERBOSE=0
VERBOSE_INTERVAL=600

# Folder log internal asli milik Roblox
RBX_LOG_DIR="/sdcard/Android/data/com.roblox.client/files/logs"

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
save_config() { cat > "$CONFIG_FILE" <<EOF
URL="$URL"
EOF
}

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

join_private_server() {
    log ""
    log "🚀 Launching Private Server Garden..."
    
    # Masa aman 3 menit buat Delta mindahin akun ke Market Trade
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$HOME/grace_until.txt"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Roblox diluncurkan. Menunggu masuk ke Market..."
}

cek_log_roblox_dc() {
    # Cari file log Roblox yang paling baru diubah/ditulis
    local LATEST_LOG; LATEST_LOG=$(ls -t "$RBX_LOG_DIR"/*.log 2>/dev/null | head -n 1)
    
    if [ -z "$LATEST_LOG" ]; then
        echo "NORMAL"
        return
    fi
    
    # Ambil 15 baris terakhir dari log game Roblox tersebut
    local LOG_TAIL; LOG_TAIL=$(tail -n 15 "$LATEST_LOG" 2>/dev/null)
    
    # Cek apakah ada kata kunci mutlak pemutusan hubungan server (Eror 288)
    if echo "$LOG_TAIL" | grep -qiE "DisconnectReason: 288|Connection lost|Disconnection|connection closed|Shutting down"; then
        echo "DC"
    else
        echo "NORMAL"
    fi
}

# ─────────────────────────────────────────
#    MAIN PROGRAM
# ─────────────────────────────────────────

if [ "$(id -u)" != "0" ]; then
    echo "⚠️ Minta akses root..."
    exec su -c "$0"
fi

load_config

if [ -z "$URL" ]; then
    clear
    echo "========================================="
    echo "    SETUP LINK PRIVATE SERVER ROBLOX     "
    echo "========================================="
    printf " Paste link private server kamu: \n> "
    read -r URL
    save_config
fi

clear
echo "========================================="
echo "    BOT RUNNING: ROBLOX LOG DETECTOR     "
echo "========================================="
log "Bot siap memantau file log internal Roblox."

join_private_server

while true; do
    sleep "$CHECK_INTERVAL"
    
    NOW=$(date +%s)
    GRACE=$(cat "$HOME/grace_until.txt" 2>/dev/null)

    # 1. PROTEKSI: CEK JIKA GAME TERTUTUP TOTAL / CRASH
    if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
        log "💥 Roblox terdeteksi crash/close! Mengembalikan ke Private Server..."
        join_private_server
        continue
    fi

    # 2. DETEKSI DC: HANYA BERAKSI SETELAH LEWAT MASA TELEPORT (GRACE PERIOD)
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        
        STATUS_GAME=$(cek_log_roblox_dc)
        
        if [ "$STATUS_GAME" = "DC" ]; then
            log "🔍 Log Roblox mendeteksi tanda Disconnect / Server Shutdown. Verifikasi dalam 5 detik..."
            sleep 5
            
            # Cek ulang untuk memastikan bukan sekadar lag kedip biasa
            if [ "$(cek_log_roblox_dc)" = "DC" ]; then
                log "🚨 POSITIF: Server Terputus (Eror 288) terkonfirmasi dari log game!"
                log "♻️ Melakukan Rejoin otomatis ke Private Server..."
                join_private_server
                continue
            fi
        fi
    fi

    # Log berkala setiap 10 menit
    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Monitor aman. Game berjalan lancar tanpa indikasi DC."
        LAST_VERBOSE=$NOW
    fi
done
