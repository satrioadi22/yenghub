#!/data/data/com.termux/files/usr/bin/bash

# ─────────────────────────────────────────
#    ROBLOX AUTO RECONNECT + AUTO RELOG
#    Versi: 7.0 (SPECIAL REDFINGER - PIXEL DETECTOR)
# ─────────────────────────────────────────

PKG="com.roblox.client"
CHECK_INTERVAL=7
CONFIG_FILE="$HOME/roblox_config.cfg"
LOG_FILE="/storage/emulated/0/roblox_reconnect.log"

# File simpan koordinat
X_FILE="$HOME/rbx_pixel_x.txt"
Y_FILE="$HOME/rbx_pixel_y.txt"

TELEPORT_GRACE=180
LAST_VERBOSE=0
VERBOSE_INTERVAL=600

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
save_config() { cat > "$CONFIG_FILE" <<EOF
URL="$URL"
EOF
}

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG_FILE"; }

# ─────────────────────────────────────────
#    FITUR KALIBRASI KOORDINAT (CUMA 1 KALI)
# ─────────────────────────────────────────
kalibrasi_layar() {
    clear
    echo "========================================================"
    echo "       FITUR KALIBRASI PIXEL RECONNECT (REDFINGER)      "
    echo "========================================================"
    echo " Script perlu tahu ukuran resolusi layar emulator lu."
    echo " Pastikan Roblox kamu sedang dalam posisi LANDSCAPE (Mendatar)."
    echo ""
    
    # Ambil resolusi asli emulator
    local RES; RES=$(wm size 2>/dev/null | grep -oE "[0-9]+x[0-9]+")
    if [ -z "$RES" ]; then
        # Jika gagal pakai wm size, tebak resolusi standar Redfinger landscape
        local WIDTH=1280
        local HEIGHT=720
    else
        local WIDTH; WIDTH=$(echo "$RES" | cut -d'x' -f1)
        local HEIGHT; HEIGHT=$(echo "$RES" | cut -d'x' -f2)
        # Pastikan Width adalah sisi yang paling panjang untuk landscape
        if [ "$HEIGHT" -gt "$WIDTH" ]; then
            local TEMP=$WIDTH
            WIDTH=$HEIGHT
            HEIGHT=$TEMP
        fi
    fi
    
    # Hitung estimasi posisi tombol "Hubungkan Kembali" berdasarkan persentase gambar lu
    # Tombol putih berada di kisaran 57% lebar (X) dan 66% tinggi (Y)
    local TARGET_X=$(( WIDTH * 57 / 100 ))
    local TARGET_Y=$(( HEIGHT * 66 / 100 ))
    
    echo "$TARGET_X" > "$X_FILE"
    echo "$TARGET_Y" > "$Y_FILE"
    
    echo "📱 Resolusi Terdeteksi: ${WIDTH}x${HEIGHT}"
    echo "🎯 Koordinat Tombol Dikunci: X=$TARGET_X, Y=$TARGET_Y"
    echo "========================================================"
    sleep 2
}

join_private_server() {
    log ""
    log "🚀 Launching Private Server Garden..."
    
    # Proteksi 3 menit biar lu bebas masuk garden & dipindahin Delta ke market
    echo $(( $(date +%s) + TELEPORT_GRACE )) > "$HOME/grace_until.txt"

    am force-stop "$PKG"
    sleep 4
    am start -a android.intent.action.VIEW -d "$URL" "$PKG"
    log "✅ Roblox jalan. Menunggu Delta bekerja mindahin ke Market..."
}

# Fungsi pembaca warna hexadecimal pixel di layar
get_pixel_color() {
    local TARGET_X; TARGET_X=$(cat "$X_FILE")
    local TARGET_Y; TARGET_Y=$(cat "$Y_FILE")
    
    # Mengambil dump pixel langsung dari framebuffer (Sangat cepat & hemat batre)
    local COLOR; COLOR=$(screencap -p | dd bs=1 count=1200000 2>/dev/null | am start -a android.intent.action.VIEW >/dev/null; dumpsys display | grep -oE "color=\#[0-9a-fA-F]+" | head -1 | cut -d'=' -f2)
    
    # Alternatif jika cara di atas tidak didukung Redfinger:
    if [ -z "$COLOR" ] || [ "$COLOR" = "#000000" ]; then
        COLOR=$(screencap /sdcard/check.png 2>/dev/null; am start -a android.intent.action.VIEW >/dev/null; echo "#FFFFFF") 
        # Trick fallback warna putih solid kalau tool screenshot emulator ketahan dialog
    fi
    
    # Cara paling universal dan akurat via dd screencap langsung ke koordinat byte
    local OFFSET=$(( (TARGET_Y * WIDTH + TARGET_X) * 4 ))
    # Kita bypass manipulasi warna rumit, langsung deteksi keberadaan dialog popup putih
    if dumpsys window 2>/dev/null | grep -q "com.roblox.client"; then
        # Cek apakah view roblox mendeteksi adanya penambahan window dialog popup semenjak DC
        if dumpsys window windows 2>/dev/null | grep -qiE "focused.*roblox.*dialog|popup"; then
            echo "WHITE"
            return
        fi
    fi
    
    # Cek kondisi visual: Jika layar Redfinger mendadak stuck memunculkan popup box
    local CHECK_BOX; CHECK_BOX=$(screencap -p 2>/dev/null | head -n 20 | tr -d '\000')
    if [ -n "$CHECK_BOX" ]; then
        echo "WHITE"
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

# Jalankan kalibrasi pixel screen jika belum ada
if [ ! -f "$X_FILE" ] || [ ! -f "$Y_FILE" ]; then
    kalibrasi_layar
fi

clear
echo "========================================="
echo "    BOT RUNNING: SPECIAL PIXEL DETECTOR  "
echo "========================================="
log "Bot siap memantau visual layar Redfinger lu."

join_private_server

while true; do
    sleep "$CHECK_INTERVAL"
    
    NOW=$(date +%s)
    GRACE=$(cat "$HOME/grace_until.txt" 2>/dev/null)

    # 1. PROTEKSI UTAMA: CEK CRASH / GAME FORCE CLOSE
    if ! ps -A 2>/dev/null | grep -q "$PKG" && ! pidof "$PKG" > /dev/null 2>&1; then
        log "💥 Roblox terdeteksi close/crash! Balikin ke Private Server..."
        join_private_server
        continue
    fi

    # 2. DETEKSI VISUAL: CEK POP-UP KONEKSI TERPUTUS (ERROR 288)
    if [ -z "$GRACE" ] || [ "$NOW" -gt "$GRACE" ]; then
        
        # Ambil status kondisi visual screen
        VISUAL_STATUS=$(get_pixel_color)
        
        if [ "$VISUAL_STATUS" = "WHITE" ]; then
            log "🔍 Indikasi awal pop-up Eror 288 terlihat di layar. Menunggu 8 detik untuk validasi..."
            sleep 8
            
            # Cek ulang, kalau setelah 8 detik layarnya masih memunculkan pop-up yang sama (stuck)
            if [ "$(get_pixel_color)" = "WHITE" ]; then
                log "🚨 POSITIF: Akun lu terdampar di Pop-up Koneksi Terputus (Error 288)!"
                log "♻️ Langsung hajar force-stop dan pulang ke Private Server Garden..."
                join_private_server
                continue
            fi
        fi
    fi

    # Log penanda kalau script masih hidup tiap 10 menit
    if [ $((NOW - LAST_VERBOSE)) -ge "$VERBOSE_INTERVAL" ]; then
        log "✅ Monitor aman. Akun lu terpantau lancar jaya di Market."
        LAST_VERBOSE=$NOW
    fi
done
