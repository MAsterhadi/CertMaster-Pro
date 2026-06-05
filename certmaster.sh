#!/usr/bin/env bash

# =========================================================
#              CERTMASTER ENTERPRISE
#        Ultimate Commercial SSL Management Suite
# =========================================================

VERSION="1.0.4"

# =========================================================
# COLOR THEME FOR TUI (WHIPTAIL)
# =========================================================
export NEWT_COLORS='
root=,black
window=,black
border=cyan,black
shadow=,black
title=green,black
button=black,cyan
actbutton=white,blue
compactbutton=black,cyan
checkbox=black,cyan
actcheckbox=white,blue
entry=green,black
label=white,black
listbox=white,black
actlistbox=black,cyan
textbox=white,black
acttextbox=black,cyan
helpline=,black
roottext=,black
'

# =========================================================
# PATHS
# =========================================================
BASE_DIR="/opt/CertMaster-Pro"
CONFIG_DIR="$BASE_DIR/config"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"
CONFIG_FILE="$CONFIG_DIR/settings.json"
LOG_FILE="$LOG_DIR/activity.log"
UPDATE_URL="https://raw.githubusercontent.com/MAsterhadi/CertMaster-Pro/main/certmaster.sh"

# =========================================================
# ROOT CHECK
# =========================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[1;31m❌ Please run as root.\033[0m"
    exit 1
fi

# =========================================================
# INIT & DEPENDENCIES
# =========================================================
mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
cat > "$CONFIG_FILE" <<EOF
{
  "telegram_bot_token": "",
  "telegram_chat_id": "",
  "cloudflare_email": "",
  "cloudflare_api_key": "",
  "domains": []
}
EOF
fi

install_dependencies() {
    PKGS=()
    command -v jq >/dev/null || PKGS+=("jq")
    command -v certbot >/dev/null || PKGS+=("certbot")
    command -v curl >/dev/null || PKGS+=("curl")
    command -v lsof >/dev/null || PKGS+=("lsof")
    command -v openssl >/dev/null || PKGS+=("openssl")
    command -v whiptail >/dev/null || PKGS+=("whiptail")

    if [ ${#PKGS[@]} -gt 0 ]; then
        apt update -y >/dev/null 2>&1
        apt install -y "${PKGS[@]}" >/dev/null 2>&1
    fi
}
install_dependencies

# =========================================================
# HELPERS
# =========================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"
}

msgbox() {
    whiptail --title " $1 " --msgbox "\n$2" 15 75
}

progress_bar_ui() {
    DURATION=$1
    TITLE=$2
    {
        for ((i=0; i<=100; i+= (100/DURATION) )); do
            echo $i
            sleep 1
        done
        echo 100
    } | whiptail --title " $TITLE " --gauge "\nProcessing... Please wait." 10 70 0
}

detect_webserver() {
    if systemctl is-active nginx >/dev/null 2>&1; then
        WEBSERVER="nginx"
    elif systemctl is-active apache2 >/dev/null 2>&1; then
        WEBSERVER="apache2"
    else
        WEBSERVER=""
    fi
}

ssl_grade() {
    DAYS=$1
    if [ $DAYS -gt 60 ]; then echo "A+"
    elif [ $DAYS -gt 30 ]; then echo "A"
    elif [ $DAYS -gt 15 ]; then echo "B"
    else echo "C"
    fi
}

# =========================================================
# TELEGRAM ALERT
# =========================================================
telegram_alert() {
    TOKEN=$(jq -r '.telegram_bot_token' "$CONFIG_FILE")
    CHAT_ID=$(jq -r '.telegram_chat_id' "$CONFIG_FILE")
    if [[ ! -z "$TOKEN" && ! -z "$CHAT_ID" && "$TOKEN" != "null" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="$1" >/dev/null
    fi
}

# =========================================================
# HEALTH MONITOR
# =========================================================
health_monitor() {
    HEALTH_OUTPUT="🩺 SYSTEM HEALTH MONITOR\n\n"
    
    command -v certbot >/dev/null && HEALTH_OUTPUT+="✔ Certbot: Installed\n" || HEALTH_OUTPUT+="❌ Certbot: Missing\n"
    systemctl is-active cron >/dev/null 2>&1 && HEALTH_OUTPUT+="✔ Cron: Active\n" || HEALTH_OUTPUT+="⚠ Cron: Inactive\n"
    ping -c 1 google.com >/dev/null 2>&1 && HEALTH_OUTPUT+="✔ Internet: Connected\n" || HEALTH_OUTPUT+="❌ Internet: Disconnected\n"
    
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
        HEALTH_OUTPUT+="⚠ Port 80: IN USE\n"
    else
        HEALTH_OUTPUT+="✔ Port 80: Available\n"
    fi

    detect_webserver
    if [[ ! -z "$WEBSERVER" ]]; then
        HEALTH_OUTPUT+="✔ Webserver: $WEBSERVER (Active)\n"
    else
        HEALTH_OUTPUT+="⚠ Webserver: None Detected\n"
    fi

    msgbox "Health Monitor" "$HEALTH_OUTPUT"
}

# =========================================================
# AUTO REPAIR
# =========================================================
auto_repair() {
    whiptail --title " Auto Repair " --yesno "Start automated system repair?\nThis will fix broken packages and restart services." 12 75
    [[ $? -ne 0 ]] && return

    progress_bar_ui 5 "Repairing System"

    apt --fix-broken install -y >/dev/null 2>&1
    detect_webserver
    [[ ! -z "$WEBSERVER" ]] && systemctl restart $WEBSERVER
    certbot renew --dry-run >/dev/null 2>&1

    log "REPAIR" "Auto repair completed"
    msgbox "Success" "Auto repair completed successfully."
}

# =========================================================
# PANEL SELECTOR (Transparent)
# =========================================================
select_panel() {
    PANEL_CHOICE=$(whiptail --title " Target Panel " --menu "Select the panel you want to secure:" 18 75 6 \
    "1" "Rebecca" \
    "2" "Marzban" \
    "3" "Pasarguard" \
    "4" "Marzneshin" \
    "5" "Custom Path" 3>&1 1>&2 2>&3)

    case $PANEL_CHOICE in
        1) TARGET_BASE_DIR="/var/lib/rebecca/certs"; PANEL_NAME="Rebecca" ;;
        2) TARGET_BASE_DIR="/var/lib/marzban/certs"; PANEL_NAME="Marzban" ;;
        3) TARGET_BASE_DIR="/var/lib/pasarguard/certs"; PANEL_NAME="Pasarguard" ;;
        4) TARGET_BASE_DIR="/var/lib/marzneshin/certs"; PANEL_NAME="Marzneshin" ;;
        5) TARGET_BASE_DIR=$(whiptail --title " Custom Path " --inputbox "Enter custom absolute path for certs:" 12 75 3>&1 1>&2 2>&3); PANEL_NAME="Custom" ;;
        *) return 1 ;;
    esac
}

# =========================================================
# INSTALL SSL
# =========================================================
install_certificate() {
    select_panel || return
    
    DOMAIN=$(whiptail --title " Domain Setup " --inputbox "Enter the domain name (e.g., app.example.com):" 12 75 3>&1 1>&2 2>&3)
    [[ -z "$DOMAIN" ]] && return

    whiptail --title " Confirmation " --yesno "📌 TARGET VERIFICATION:\n\nDomain: $DOMAIN\nTarget Panel: $PANEL_NAME\nInstall Path: $TARGET_BASE_DIR/$DOMAIN\n\nProceed with these settings?" 18 75
    [[ $? -ne 0 ]] && return

    CHALLENGE=$(whiptail --title " SSL Challenge Method " --menu "Select validation method (Zero-Downtime Options):" 18 85 4 \
    "1" "Webroot (No Downtime - Requires Nginx/Apache)" \
    "2" "Cloudflare DNS (No Downtime - Most Secure)" \
    "3" "Standalone (Requires temporary Port 80 availability)" 3>&1 1>&2 2>&3)

    case $CHALLENGE in
        1)
            WEBROOT_PATH=$(whiptail --title " Webroot Path " --inputbox "Enter web server root path:" 12 75 "/var/www/html" 3>&1 1>&2 2>&3)
            CERT_CMD="certbot certonly --webroot -w $WEBROOT_PATH -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email"
            ;;
        2)
            CF_EMAIL=$(jq -r '.cloudflare_email' "$CONFIG_FILE")
            CF_KEY=$(jq -r '.cloudflare_api_key' "$CONFIG_FILE")
            if [[ -z "$CF_EMAIL" || "$CF_EMAIL" == "null" || -z "$CF_KEY" || "$CF_KEY" == "null" ]]; then
                CF_EMAIL=$(whiptail --title " Cloudflare API " --inputbox "Enter Cloudflare Email:" 12 75 3>&1 1>&2 2>&3)
                CF_KEY=$(whiptail --title " Cloudflare API " --inputbox "Enter Cloudflare API Key:" 12 75 3>&1 1>&2 2>&3)
                TMP=$(jq --arg e "$CF_EMAIL" --arg k "$CF_KEY" '.cloudflare_email=$e | .cloudflare_api_key=$k' "$CONFIG_FILE")
                echo "$TMP" > "$CONFIG_FILE"
            fi
            mkdir -p ~/.secrets
            cat > ~/.secrets/cloudflare.ini <<EOF
dns_cloudflare_email = $CF_EMAIL
dns_cloudflare_api_key = $CF_KEY
EOF
            chmod 600 ~/.secrets/cloudflare.ini
            CERT_CMD="certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email"
            ;;
        3)
            if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
                whiptail --title " Port 80 in Use " --yesno "Port 80 is active. Stop webserver temporarily to issue SSL?" 12 75
                if [[ $? -eq 0 ]]; then
                    detect_webserver
                    [[ ! -z "$WEBSERVER" ]] && systemctl stop $WEBSERVER
                else
                    return
                fi
            fi
            CERT_CMD="certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email"
            ;;
        *) return ;;
    esac

    # Execute
    clear
    echo -e "\033[1;36mGenerating SSL Certificate for $DOMAIN...\033[0m"
    $CERT_CMD

    if [ $? -eq 0 ]; then
        FINAL_PATH="$TARGET_BASE_DIR/$DOMAIN"
        mkdir -p "$FINAL_PATH"
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$FINAL_PATH/"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$FINAL_PATH/"
        chmod 644 "$FINAL_PATH/fullchain.pem"
        chmod 600 "$FINAL_PATH/privkey.pem"

        TMP=$(jq --arg d "$DOMAIN" --arg p "$FINAL_PATH" --arg pn "$PANEL_NAME" '.domains += [{"main_domain":$d, "install_path":$p, "panel":$pn}]' "$CONFIG_FILE")
        echo "$TMP" > "$CONFIG_FILE"

        log "SUCCESS" "Installed SSL for $DOMAIN on $PANEL_NAME"
        telegram_alert "✅ SSL Installed Successfully\nDomain: $DOMAIN\nPanel: $PANEL_NAME"
        msgbox "Success" "Certificate generated and copied to $PANEL_NAME!"
    else
        log "ERROR" "SSL failed for $DOMAIN"
        telegram_alert "❌ SSL Generation Failed\nDomain: $DOMAIN"
        msgbox "Error" "Failed to generate certificate. Check logs."
    fi

    detect_webserver
    [[ ! -z "$WEBSERVER" && "$CHALLENGE" == "3" ]] && systemctl start $WEBSERVER
}

# =========================================================
# WILDCARD SSL
# =========================================================
wildcard_ssl() {
    DOMAIN=$(whiptail --title " Wildcard SSL " --inputbox "Enter base domain (e.g., example.com):" 12 75 3>&1 1>&2 2>&3)
    [[ -z "$DOMAIN" ]] && return

    CF_EMAIL=$(jq -r '.cloudflare_email' "$CONFIG_FILE")
    CF_KEY=$(jq -r '.cloudflare_api_key' "$CONFIG_FILE")

    if [[ -z "$CF_EMAIL" || "$CF_EMAIL" == "null" ]]; then
        CF_EMAIL=$(whiptail --title " Cloudflare API " --inputbox "Enter Cloudflare Email:" 12 75 3>&1 1>&2 2>&3)
        CF_KEY=$(whiptail --title " Cloudflare API " --inputbox "Enter Cloudflare API Key:" 12 75 3>&1 1>&2 2>&3)
        TMP=$(jq --arg e "$CF_EMAIL" --arg k "$CF_KEY" '.cloudflare_email=$e | .cloudflare_api_key=$k' "$CONFIG_FILE")
        echo "$TMP" > "$CONFIG_FILE"
    fi

    mkdir -p ~/.secrets
    cat > ~/.secrets/cloudflare.ini <<EOF
dns_cloudflare_email = $CF_EMAIL
dns_cloudflare_api_key = $CF_KEY
EOF
    chmod 600 ~/.secrets/cloudflare.ini

    clear
    echo -e "\033[1;36mGenerating Wildcard SSL for *.$DOMAIN...\033[0m"
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d "*.$DOMAIN" -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    
    if [ $? -eq 0 ]; then
        msgbox "Success" "Wildcard SSL generated successfully."
    else
        msgbox "Error" "Failed to generate Wildcard SSL."
    fi
}

# =========================================================
# DELETE CERTIFICATE (SMART SCAN)
# =========================================================
delete_certificate() {
    DOMAINS_LIST=()

    # اسکن مستقیم از هسته Certbot برای پیدا کردن تمام دامنه‌های سرور
    for cert_dir in /etc/letsencrypt/live/*; do
        [ -d "$cert_dir" ] || continue
        DOMAIN=$(basename "$cert_dir")
        [ "$DOMAIN" == "README" ] && continue

        # خواندن اسم پنل از دیتابیس در صورت وجود
        PANEL_INFO=$(jq -r --arg d "$DOMAIN" '.domains[] | select(.main_domain==$d) | .panel' "$CONFIG_FILE" 2>/dev/null)
        [[ -z "$PANEL_INFO" || "$PANEL_INFO" == "null" ]] && PANEL_INFO="Unknown"

        DOMAINS_LIST+=("$DOMAIN" "[$PANEL_INFO]")
    done

    if [ ${#DOMAINS_LIST[@]} -eq 0 ]; then
        msgbox "Empty" "No managed certificates found in Certbot."
        return
    fi

    SELECTED_DOMAIN=$(whiptail --title " Delete Certificate " --menu "Select domain to COMPLETELY remove:" 20 75 10 "${DOMAINS_LIST[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$SELECTED_DOMAIN" ]] && return

    whiptail --title " Warning " --yesno "Are you sure you want to completely DELETE $SELECTED_DOMAIN?\nThis removes it from Certbot, the target panel, and database." 12 75
    [[ $? -ne 0 ]] && return

    # حذف از سرتبات
    certbot delete --cert-name "$SELECTED_DOMAIN" --non-interactive >/dev/null 2>&1
    
    # حذف مسیر گواهینامه در پنل 
    INSTALL_PATH=$(jq -r --arg d "$SELECTED_DOMAIN" '.domains[] | select(.main_domain==$d) | .install_path' "$CONFIG_FILE" 2>/dev/null)
    if [[ ! -z "$INSTALL_PATH" && "$INSTALL_PATH" != "null" && -d "$INSTALL_PATH" ]]; then
        rm -rf "$INSTALL_PATH"
    fi

    # پاک کردن از دیتابیس محلی
    TMP=$(jq --arg d "$SELECTED_DOMAIN" '.domains |= map(select(.main_domain != $d))' "$CONFIG_FILE" 2>/dev/null)
    [[ ! -z "$TMP" ]] && echo "$TMP" > "$CONFIG_FILE"

    log "DELETE" "Removed domain $SELECTED_DOMAIN"
    msgbox "Success" "Domain $SELECTED_DOMAIN has been removed."
}

# =========================================================
# SMART AUTO RENEW & SYNC
# =========================================================
setup_auto_renew() {
    CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook \"/usr/local/bin/certmaster --sync\" >> $LOG_FILE 2>&1"
    
    whiptail --title " Smart Auto-Renew " --yesno "Enable Smart Auto-Renew?\n\nIt automatically checks daily and ONLY copies files to your panels if a certificate was successfully renewed." 15 75
    if [ $? -eq 0 ]; then
        crontab -l 2>/dev/null | grep -v "certmaster" | crontab -
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        log "INFO" "Smart Auto-Renew Enabled"
        msgbox "Enabled" "Smart Auto-Renew is active."
    fi
}

sync_certificates() {
    jq -c '.domains[]' "$CONFIG_FILE" | while read i; do
        DOMAIN=$(echo "$i" | jq -r '.main_domain')
        INSTALL_PATH=$(echo "$i" | jq -r '.install_path')
        if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
            mkdir -p "$INSTALL_PATH"
            cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$INSTALL_PATH/"
            cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$INSTALL_PATH/"
            chmod 644 "$INSTALL_PATH/fullchain.pem"
            chmod 600 "$INSTALL_PATH/privkey.pem"
            log "SYNC" "Synced SSL for $DOMAIN"
        fi
    done
    detect_webserver
    [[ ! -z "$WEBSERVER" ]] && systemctl reload $WEBSERVER >/dev/null 2>&1
}

if [[ "$1" == "--sync" ]]; then
    sync_certificates
    telegram_alert "🔄 CertMaster: Auto-Renew & Sync Hook Executed!"
    exit 0
fi

# =========================================================
# LIST CERTIFICATES (SMART DEEP SCAN)
# =========================================================
list_certificates() {
    CERTS=()
    MENUS=()
    SEEN_DOMAINS=()
    INDEX=1

    SEARCH_DIRS=(
        "/etc/letsencrypt/live"
        "/var/lib/rebecca/certs"
        "/var/lib/marzban/certs"
        "/var/lib/pasarguard/certs"
        "/var/lib/marzneshin/certs"
    )

    for base_dir in "${SEARCH_DIRS[@]}"; do
        [ -d "$base_dir" ] || continue
        
        for cert_dir in "$base_dir"/*; do
            [ -d "$cert_dir" ] || continue
            DOMAIN=$(basename "$cert_dir")
            [ "$DOMAIN" == "README" ] && continue
            
            if [[ " ${SEEN_DOMAINS[@]} " =~ " ${DOMAIN} " ]]; then
                continue
            fi

            CERT_FILE="$cert_dir/fullchain.pem"
            if [ ! -f "$CERT_FILE" ]; then
                CERT_FILE=$(find "$cert_dir" -maxdepth 1 -name "*.crt" -o -name "*.pem" | head -n 1)
            fi
            
            [ -z "$CERT_FILE" ] || [ ! -f "$CERT_FILE" ] && continue

            EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
            [ -z "$EXPIRY_DATE" ] && continue
            
            DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))
            GRADE=$(ssl_grade $DAYS_LEFT)
            
            SEEN_DOMAINS+=("$DOMAIN")
            CERTS+=("$CERT_FILE|$DOMAIN") 
            MENUS+=("$INDEX" "$DOMAIN | Days: $DAYS_LEFT | Grade: $GRADE")
            ((INDEX++))
        done
    done

    if [ ${#MENUS[@]} -eq 0 ]; then
        msgbox "Certificates" "No SSL certificates found on the server."
        return
    fi

    CHOICE=$(whiptail --title " SSL Certificates " --menu "Select a domain to view details:" 22 80 12 "${MENUS[@]}" 3>&1 1>&2 2>&3)
    [[ -z "$CHOICE" ]] && return

    SELECTED_INDEX=$((CHOICE - 1))
    SELECTED_DATA="${CERTS[$SELECTED_INDEX]}"
    
    EXACT_CERT_FILE="${SELECTED_DATA%%|*}"
    DOMAIN="${SELECTED_DATA##*|}"
    
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$EXACT_CERT_FILE" | cut -d= -f2)
    DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))
    GRADE=$(ssl_grade $DAYS_LEFT)
    
    PANEL_INFO=$(jq -r --arg d "$DOMAIN" '.domains[] | select(.main_domain==$d) | .panel' "$CONFIG_FILE" 2>/dev/null)
    [[ -z "$PANEL_INFO" || "$PANEL_INFO" == "null" ]] && PANEL_INFO="Unknown / Manual Install"

    INFO="🌐 Domain: $DOMAIN\n"
    INFO+="📦 Linked Panel DB: $PANEL_INFO\n"
    INFO+="📂 Detected Path: $(dirname "$EXACT_CERT_FILE")\n"
    INFO+="📅 Expire Date: $(date -d "$EXPIRY_DATE" +%Y-%m-%d)\n"
    INFO+="⏳ Days Left: $DAYS_LEFT days\n"
    INFO+="🏆 SSL Grade: $GRADE\n"

    msgbox "Certificate Info" "$INFO"
}

# =========================================================
# DASHBOARD
# =========================================================
dashboard() {
    TOTAL=$(find /etc/letsencrypt/live -maxdepth 1 -type d 2>/dev/null | wc -l)
    [[ $TOTAL -gt 0 ]] && TOTAL=$((TOTAL - 1))
    
    DASH="📦 Total Certificates: $TOTAL\n"
    DASH+="⚡ Enterprise Version: $VERSION\n"
    DASH+="📄 Log File: $LOG_FILE"
    
    msgbox "Live Dashboard" "$DASH"
}

# =========================================================
# UPDATE SCRIPT
# =========================================================
update_script() {
    whiptail --title " Update " --yesno "Check and install the latest update?" 12 75
    [[ $? -ne 0 ]] && return

    HTTP_CODE=$(curl -H 'Cache-Control: no-cache' -s -w "%{http_code}" -o /tmp/certmaster_new.sh "$UPDATE_URL")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        mv /tmp/certmaster_new.sh /opt/CertMaster-Pro/certmaster.sh
        chmod +x /opt/CertMaster-Pro/certmaster.sh
        
        cp /opt/CertMaster-Pro/certmaster.sh /usr/local/bin/certmaster
        chmod +x /usr/local/bin/certmaster
        
        log "UPDATE" "Script updated to version $VERSION"
        msgbox "Success" "CertMaster updated successfully! Please run 'certmaster' again to see changes."
        exit 0
    else
        msgbox "Error" "Update failed. Error Code: $HTTP_CODE"
    fi
}

# =========================================================
# MAIN MENU
# =========================================================
main_menu() {
    while true; do
        OPTION=$(whiptail --title " CERTMASTER v$VERSION " --menu "Advanced SSL Management Platform" 24 85 12 \
        "1" "Install New SSL Certificate" \
        "2" "Wildcard SSL (Cloudflare DNS)" \
        "3" "Delete Managed Certificate" \
        "4" "List Certificates & Health" \
        "5" "System Health Monitor" \
        "6" "Auto Repair System" \
        "7" "Setup Smart Auto-Renew" \
        "8" "Force Sync to Panels" \
        "9" "Live Dashboard" \
        "10" "Update Script" \
        "0" "Exit CertMaster" 3>&1 1>&2 2>&3)

        if [ $? -ne 0 ]; then clear; break; fi

        case $OPTION in
            1) install_certificate ;;
            2) wildcard_ssl ;;
            3) delete_certificate ;;
            4) list_certificates ;;
            5) health_monitor ;;
            6) auto_repair ;;
            7) setup_auto_renew ;;
            8) sync_certificates; msgbox "Sync" "Manual sync executed successfully." ;;
            9) dashboard ;;
            10) update_script ;;
            0) clear; exit 0 ;;
        esac
    done
}

# =========================================================
# START
# =========================================================
main_menu
