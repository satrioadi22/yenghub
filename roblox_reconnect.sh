#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 9.0 (NETWORK ANALYZER - SHUTDOWN FIX)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=8
CONFIG_FILE="$HOME/roblox_config.cfg"
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"

TELEPORT_GRACE=180
LAST_VERBOSE=0
VERBOSE_INTERVAL=600

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
save_config() { cat > "$CONFIG_FILE" <<EOF
URL="$URL"
EOF
}

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

join_private_server() {
    log ""
    log "🚀 Launching Private Server Garden..."
    
    # Kunci masa aman 3 menit buat Delta mindahin akun lu dari Garden ke Market
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$HOME/grace_until.txt"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Roblox diluncurkan. Menunggu masuk ke Market..."
}

cek_koneksi_game() {
    # Ambil PID (Process ID) dari game Roblox yang lagi jalan
    local RBX_PID; RBX_PID=$(pidof "$PKG" 2>/dev/null || ps -A 2>/dev/null | grep "$PKG" | awk '{print $2}' | head -n 1)
    
    if [ -z "$RBX_PID" ]; then
        echo "CRASH"
        return
    fi
    
    # Cek apakah PID Roblox tersebut punya koneksi jaringan aktif (ESTABLISHED)
    # Kita cek via netstat atau langsung ke inet internal proc Android
    local NET_CHECK; NET_CHECK=$(netstat -anp 2>/dev/null | grep "$RBX_PID" | grep -i "ESTABLISHED")
    
    if [ -z "$NET_CHECK" ]; then
        # Cek cadangan lewat file socket internal linux/android jika netstat dibatasi root
        NET_CHECK=$(cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -v "00000000:0000" | awk '{print $4}' | grep "01")
    fi

    if [ -n "$NET_CHECK" ]; then
        echo "CONNECTED"
    else
        echo "DISCONNECTED"
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
echo "    BOT RUNNING: NETWORK CONNECTION MODE "
echo "========================================="
log "Bot siap memantau status jaringan internet Roblox."

join_private_server

while true; do
    sleep "$CHECK_INTERVAL"
    
    NOW=$(date +%s)
    GRACE=$(cat "$HOME/grace_until.txt" 2>/dev/null)
    
    STATUS_GAME=$(cek_koneksi_game)

    # 1. PROTEKSI: CEK JIKA GAME TERTUTUP TOTAL / CRASH
    if [ "$STATUS_GAME" = "CRASH" ]; then
        log "💥 Roblox terdeteksi close/crash! Mengembalikan ke Private Server..."
        join_private_server
        continue
    fi

    # 2. DETEKSI SHUTDOWN (EROR 288): HANYA BERAKSI SETELAH LEWAT MASA GRACE PERIOD
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        
        if [ "$STATUS_GAME" = "DISCONNECTED" ]; then
            log "🔍 Deteksi awal: Game Roblox kehilangan koneksi internet. Verifikasi dalam 10 detik..."
            sleep 10
            
            # Cek ulang, kalau setelah 10 detik internet game-nya tetep mati (berarti beneran stuck di screen Eror 288)
            if [ "$(cek_koneksi_game)" = "DISCONNECTED" ]; then
                log "🚨 POSITIF: Game terputus dari server (Error 288 / Server Mati)!"
                log "♻️ Melakukan Rejoin otomatis kembali ke Private Server..."
                join_private_server
                continue
            fi
        fi
    fi

    # Log berkala setiap 10 menit
    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Monitor aman. Koneksi internet Roblox ke server Market terpantau stabil."
        LAST_VERBOSE=$NOW
    fi
done
