#!/usr/bin/env bash

# =========================================================
#              CERTMASTER ENTERPRISE
#        Ultimate Commercial SSL Management Suite
#                 (Modern CLI Edition)
# =========================================================

VERSION="1.0.2 CLI"

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
# NEON COLORS
# =========================================================
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NEON_BLUE='\033[38;5;45m'
NEON_GREEN='\033[38;5;46m'
NEON_PINK='\033[38;5;213m'
GRAY='\033[38;5;245m'

# =========================================================
# ROOT CHECK & INIT
# =========================================================
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Please run as root.${RESET}"
    exit 1
fi

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

# =========================================================
# UI COMPONENTS
# =========================================================
ui_header() {
    clear
    echo -e "${NEON_BLUE}${BOLD}"
    echo "╭───────────────────────────────────────────────────────────────────────────────╮"
    echo "│                       CERTMASTER ENTERPRISE v$VERSION                       │"
    echo "│                    Advanced SSL Management Terminal UI                        │"
    echo "╰───────────────────────────────────────────────────────────────────────────────╯"
    echo -e "${RESET}"
}

success() { echo -e "${NEON_GREEN}[✔] $1${RESET}"; }
error()   { echo -e "${RED}[✘] $1${RESET}"; }
warning() { echo -e "${YELLOW}[⚠] $1${RESET}"; }
info()    { echo -e "${CYAN}[i] $1${RESET}"; }
log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG_FILE"; }

pause_screen() {
    echo
    echo -e "${GRAY}Press [ENTER] to return to menu...${RESET}"
    read -r
}

progress_bar() {
    DURATION=$1
    TITLE=$2
    echo -e "${NEON_PINK}➜ $TITLE${RESET}"
    for ((i=0; i<=DURATION; i++)); do
        PERCENT=$((i * 100 / DURATION))
        printf "\r${NEON_BLUE}["
        for ((j=0; j<i; j++)); do printf "█"; done
        for ((j=i; j<DURATION; j++)); do printf "░"; done
        printf "] %d%%${RESET}" "$PERCENT"
        sleep 0.05
    done
    echo
}

# =========================================================
# CORE FUNCTIONS
# =========================================================
detect_webserver() {
    if systemctl is-active nginx >/dev/null 2>&1; then WEBSERVER="nginx"
    elif systemctl is-active apache2 >/dev/null 2>&1; then WEBSERVER="apache2"
    else WEBSERVER=""
    fi
}

ssl_grade() {
    DAYS=$1
    if ! [[ "$DAYS" =~ ^-?[0-9]+$ ]]; then
        echo -e "${RED}ERR${RESET}"
        return
    fi

    if [ $DAYS -gt 60 ]; then echo -e "${NEON_GREEN}A+${RESET}"
    elif [ $DAYS -gt 30 ]; then echo -e "${GREEN}A${RESET}"
    elif [ $DAYS -gt 15 ]; then echo -e "${YELLOW}B${RESET}"
    else echo -e "${RED}C${RESET}"
    fi
}

telegram_alert() {
    TOKEN=$(jq -r '.telegram_bot_token' "$CONFIG_FILE" 2>/dev/null)
    CHAT_ID=$(jq -r '.telegram_chat_id' "$CONFIG_FILE" 2>/dev/null)
    if [[ ! -z "$TOKEN" && ! -z "$CHAT_ID" && "$TOKEN" != "null" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="$1" >/dev/null
    fi
}

# =========================================================
# 1. INSTALL SSL
# =========================================================
install_certificate() {
    ui_header
    echo -e "${NEON_PINK}--- SELECT TARGET PANEL ---${RESET}"
    echo -e " ${CYAN}1)${RESET} Rebecca"
    echo -e " ${CYAN}2)${RESET} Marzban"
    echo -e " ${CYAN}3)${RESET} Pasarguard"
    echo -e " ${CYAN}4)${RESET} Marzneshin"
    echo -e " ${CYAN}5)${RESET} Custom Path"
    echo
    read -p "➜ Enter panel number [1-5]: " panel_choice

    case $panel_choice in
        1) TARGET_BASE_DIR="/var/lib/rebecca/certs"; PANEL_NAME="Rebecca" ;;
        2) TARGET_BASE_DIR="/var/lib/marzban/certs"; PANEL_NAME="Marzban" ;;
        3) TARGET_BASE_DIR="/var/lib/pasarguard/certs"; PANEL_NAME="Pasarguard" ;;
        4) TARGET_BASE_DIR="/var/lib/marzneshin/certs"; PANEL_NAME="Marzneshin" ;;
        5) read -p "➜ Enter custom absolute path: " TARGET_BASE_DIR; PANEL_NAME="Custom" ;;
        *) error "Invalid choice."; pause_screen; return ;;
    esac

    echo
    read -p "➜ Enter the domain name (e.g. app.example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && return

    echo
    echo -e "${NEON_PINK}--- SELECT CHALLENGE METHOD ---${RESET}"
    echo -e " ${CYAN}1)${RESET} Webroot (No Downtime - Nginx/Apache)"
    echo -e " ${CYAN}2)${RESET} Cloudflare DNS (No Downtime)"
    echo -e " ${CYAN}3)${RESET} Standalone (Requires Port 80)"
    echo
    read -p "➜ Enter method number [1-3]: " challenge_choice

    case $challenge_choice in
        1)
            read -p "➜ Enter webroot path [/var/www/html]: " WEBROOT_PATH
            WEBROOT_PATH=${WEBROOT_PATH:-/var/www/html}
            CERT_CMD="certbot certonly --webroot -w $WEBROOT_PATH -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email"
            ;;
        2)
            CF_EMAIL=$(jq -r '.cloudflare_email' "$CONFIG_FILE")
            CF_KEY=$(jq -r '.cloudflare_api_key' "$CONFIG_FILE")
            if [[ -z "$CF_EMAIL" || "$CF_EMAIL" == "null" ]]; then
                read -p "➜ Enter Cloudflare Email: " CF_EMAIL
                read -p "➜ Enter Cloudflare API Key: " CF_KEY
                TMP=$(jq --arg e "$CF_EMAIL" --arg k "$CF_KEY" '.cloudflare_email=$e | .cloudflare_api_key=$k' "$CONFIG_FILE")
                echo "$TMP" > "$CONFIG_FILE"
            fi
            mkdir -p ~/.secrets
            echo -e "dns_cloudflare_email = $CF_EMAIL\ndns_cloudflare_api_key = $CF_KEY" > ~/.secrets/cloudflare.ini
            chmod 600 ~/.secrets/cloudflare.ini
            CERT_CMD="certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email"
            ;;
        3)
            if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
                warning "Port 80 is in use!"
                read -p "➜ Stop webserver temporarily? (y/n): " stop_web
                if [[ "$stop_web" =~ ^[Yy]$ ]]; then
                    detect_webserver
                    [[ ! -z "$WEBSERVER" ]] && systemctl stop $WEBSERVER
                else
                    error "Operation aborted."; pause_screen; return
                fi
            fi
            CERT_CMD="certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email"
            ;;
        *) error "Invalid choice."; pause_screen; return ;;
    esac

    echo
    progress_bar 20 "Requesting Certificate for $DOMAIN..."
    $CERT_CMD >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        FINAL_PATH="$TARGET_BASE_DIR/$DOMAIN"
        mkdir -p "$FINAL_PATH"
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$FINAL_PATH/"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$FINAL_PATH/"
        chmod 644 "$FINAL_PATH/fullchain.pem"
        chmod 600 "$FINAL_PATH/privkey.pem"

        TMP=$(jq --arg d "$DOMAIN" --arg p "$FINAL_PATH" --arg pn "$PANEL_NAME" '.domains += [{"main_domain":$d, "install_path":$p, "panel":$pn}]' "$CONFIG_FILE")
        echo "$TMP" > "$CONFIG_FILE"

        success "Certificate successfully installed to $PANEL_NAME!"
        log "SUCCESS" "Installed SSL for $DOMAIN"
        telegram_alert "✅ SSL Installed\nDomain: $DOMAIN\nPanel: $PANEL_NAME"
    else
        error "Failed to generate certificate. Please check certbot logs."
        log "ERROR" "SSL failed for $DOMAIN"
    fi

    detect_webserver
    [[ ! -z "$WEBSERVER" && "$challenge_choice" == "3" ]] && systemctl start $WEBSERVER
    pause_screen
}

# =========================================================
# 2. WILDCARD SSL
# =========================================================
wildcard_ssl() {
    ui_header
    echo -e "${NEON_PINK}--- GENERATE WILDCARD SSL ---${RESET}"
    read -p "➜ Enter base domain (e.g. example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && return

    CF_EMAIL=$(jq -r '.cloudflare_email' "$CONFIG_FILE")
    CF_KEY=$(jq -r '.cloudflare_api_key' "$CONFIG_FILE")
    if [[ -z "$CF_EMAIL" || "$CF_EMAIL" == "null" ]]; then
        read -p "➜ Enter Cloudflare Email: " CF_EMAIL
        read -p "➜ Enter Cloudflare API Key: " CF_KEY
        TMP=$(jq --arg e "$CF_EMAIL" --arg k "$CF_KEY" '.cloudflare_email=$e | .cloudflare_api_key=$k' "$CONFIG_FILE")
        echo "$TMP" > "$CONFIG_FILE"
    fi
    mkdir -p ~/.secrets
    echo -e "dns_cloudflare_email = $CF_EMAIL\ndns_cloudflare_api_key = $CF_KEY" > ~/.secrets/cloudflare.ini
    chmod 600 ~/.secrets/cloudflare.ini

    echo
    progress_bar 25 "Requesting Wildcard Certificate..."
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials ~/.secrets/cloudflare.ini -d "*.$DOMAIN" -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        success "Wildcard SSL generated successfully for *.$DOMAIN!"
    else
        error "Failed to generate Wildcard SSL."
    fi
    pause_screen
}

# =========================================================
# GET DOMAINS CORE (Shared by List and Delete)
# =========================================================
get_scanned_domains() {
    CERTS_LIST=()
    SEEN_DOMAINS=()
    
    # اولویت اسکن تغییر یافت: ابتدا پنل‌ها اسکن می‌شوند تا مسیر و هویت دقیق ثبت شود
    SEARCH_DIRS=(
        "/var/lib/rebecca/certs"
        "/var/lib/marzban/certs"
        "/var/lib/pasarguard/certs"
        "/var/lib/marzneshin/certs"
        "/etc/letsencrypt/live"
    )

    for base_dir in "${SEARCH_DIRS[@]}"; do
        [ -d "$base_dir" ] || continue
        for cert_dir in "$base_dir"/*; do
            [ -d "$cert_dir" ] || continue
            DOMAIN=$(basename "$cert_dir")
            [ "$DOMAIN" == "README" ] && continue
            
            if [[ " ${SEEN_DOMAINS[@]} " =~ " ${DOMAIN} " ]]; then continue; fi

            CERT_FILE="$cert_dir/fullchain.pem"
            if [ ! -f "$CERT_FILE" ]; then
                CERT_FILE=$(find "$cert_dir" -maxdepth 1 -name "*.crt" -o -name "*.pem" 2>/dev/null | head -n 1)
            fi
            
            [ -z "$CERT_FILE" ] || [ ! -f "$CERT_FILE" ] && continue

            EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
            if [ -z "$EXPIRY_DATE" ]; then continue; fi
            
            EXP_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
            CUR_EPOCH=$(date +%s)
            
            if [[ -z "$EXP_EPOCH" ]]; then continue; fi
            DAYS_LEFT=$(( (EXP_EPOCH - CUR_EPOCH) / 86400 ))
            
            # بررسی دیتابیس لوکال
            PANEL_INFO=$(jq -r --arg d "$DOMAIN" '.domains[] | select(.main_domain==$d) | .panel' "$CONFIG_FILE" 2>/dev/null)
            
            # تشخیص هوشمند پنل از روی آدرس پوشه در صورت نبود در دیتابیس
            if [[ -z "$PANEL_INFO" || "$PANEL_INFO" == "null" ]]; then
                if [[ "$base_dir" == *"/rebecca/"* ]]; then PANEL_INFO="Rebecca"
                elif [[ "$base_dir" == *"/marzban/"* ]]; then PANEL_INFO="Marzban"
                elif [[ "$base_dir" == *"/pasarguard/"* ]]; then PANEL_INFO="Pasarguard"
                elif [[ "$base_dir" == *"/marzneshin/"* ]]; then PANEL_INFO="Marzneshin"
                else PANEL_INFO="Certbot/Standalone"
                fi
            fi

            SEEN_DOMAINS+=("$DOMAIN")
            CERTS_LIST+=("$DOMAIN|$DAYS_LEFT|$PANEL_INFO|$CERT_FILE") 
        done
    done
}

# =========================================================
# 3. LIST CERTIFICATES
# =========================================================
list_certificates() {
    ui_header
    echo -e "${NEON_PINK}--- MANAGED CERTIFICATES ---${RESET}"
    echo
    
    get_scanned_domains

    if [ ${#CERTS_LIST[@]} -eq 0 ]; then
        warning "No valid SSL certificates found on the server."
        pause_screen
        return
    fi

    printf "${CYAN}%-4s %-65s %-15s %-10s %-8s${RESET}\n" "ID" "DOMAIN" "PANEL" "DAYS LEFT" "GRADE"
    echo -e "${GRAY}-------------------------------------------------------------------------------------------------------------${RESET}"

    INDEX=1
    for item in "${CERTS_LIST[@]}"; do
        IFS='|' read -r d_name d_days d_panel d_file <<< "$item"
        GRADE=$(ssl_grade "$d_days")
        printf "%-4s %-65s %-15s %-10s %-8b\n" "[$INDEX]" "$d_name" "$d_panel" "$d_days" "$GRADE"
        ((INDEX++))
    done

    echo
    echo -e "${GRAY}0) Return to Main Menu${RESET}"
    echo
    read -p "➜ Select ID for details (or 0 to exit): " CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -le ${#CERTS_LIST[@]} ]; then
        SELECTED_INDEX=$((CHOICE - 1))
        IFS='|' read -r d_name d_days d_panel d_file <<< "${CERTS_LIST[$SELECTED_INDEX]}"
        
        CERT_DIR=$(dirname "$d_file")
        
        ui_header
        echo -e "${NEON_PINK}--- CERTIFICATE DETAILS ---${RESET}"
        echo -e "${CYAN}🌐 Domain:${RESET}       $d_name"
        echo -e "${CYAN}📦 Active Panel:${RESET} $d_panel"
        echo -e "${CYAN}📂 Cert File:${RESET}    $CERT_DIR/fullchain.pem"
        echo -e "${CYAN}🔑 Private Key:${RESET}  $CERT_DIR/privkey.pem"
        echo -e "${CYAN}⏳ Days Left:${RESET}    $d_days days"
        echo -e "${CYAN}🏆 SSL Grade:${RESET}    $(ssl_grade "$d_days")"
    fi
    pause_screen
}

# =========================================================
# 4. DELETE CERTIFICATE (DEEP CLEAN)
# =========================================================
delete_certificate() {
    ui_header
    echo -e "${NEON_PINK}--- DELETE CERTIFICATES ---${RESET}"
    echo
    
    get_scanned_domains

    if [ ${#CERTS_LIST[@]} -eq 0 ]; then
        warning "No SSL certificates found to delete."
        pause_screen
        return
    fi

    printf "${CYAN}%-4s %-65s %-15s${RESET}\n" "ID" "DOMAIN TO DELETE" "DETECTED IN"
    echo -e "${GRAY}-----------------------------------------------------------------------------------------${RESET}"

    INDEX=1
    for item in "${CERTS_LIST[@]}"; do
        IFS='|' read -r d_name d_days d_panel d_file <<< "$item"
        printf "%-4s %-65s %-15s\n" "[$INDEX]" "$d_name" "$d_panel"
        ((INDEX++))
    done

    echo
    echo -e "${GRAY}0) Cancel and Return${RESET}"
    echo
    read -p "➜ Enter the ID of the domain to completely wipe: " CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt 0 ] && [ "$CHOICE" -le ${#CERTS_LIST[@]} ]; then
        SELECTED_INDEX=$((CHOICE - 1))
        IFS='|' read -r d_name d_days d_panel d_file <<< "${CERTS_LIST[$SELECTED_INDEX]}"
        
        echo
        warning "You are about to completely wipe: $d_name"
        read -p "➜ Are you absolutely sure? (Type 'y' to confirm): " confirm
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            progress_bar 15 "Purging $d_name from server..."
            
            certbot delete --cert-name "$d_name" --non-interactive >/dev/null 2>&1
            
            rm -rf "/etc/letsencrypt/live/$d_name" 2>/dev/null
            rm -rf "/etc/letsencrypt/archive/$d_name" 2>/dev/null
            rm -f "/etc/letsencrypt/renewal/$d_name.conf" 2>/dev/null
            
            rm -rf "/var/lib/rebecca/certs/$d_name" 2>/dev/null
            rm -rf "/var/lib/marzban/certs/$d_name" 2>/dev/null
            rm -rf "/var/lib/pasarguard/certs/$d_name" 2>/dev/null
            rm -rf "/var/lib/marzneshin/certs/$d_name" 2>/dev/null
            
            INSTALL_PATH=$(jq -r --arg d "$d_name" '.domains[] | select(.main_domain==$d) | .install_path' "$CONFIG_FILE" 2>/dev/null)
            if [[ ! -z "$INSTALL_PATH" && "$INSTALL_PATH" != "null" && -d "$INSTALL_PATH" ]]; then
                rm -rf "$INSTALL_PATH" 2>/dev/null
            fi

            TMP=$(jq --arg d "$d_name" '.domains |= map(select(.main_domain != $d))' "$CONFIG_FILE" 2>/dev/null)
            [[ ! -z "$TMP" ]] && echo "$TMP" > "$CONFIG_FILE"

            success "Domain $d_name completely obliterated from the server."
            log "DELETE" "Wiped domain $d_name"
        else
            info "Deletion cancelled."
        fi
    fi
    pause_screen
}

# =========================================================
# 5. HEALTH MONITOR
# =========================================================
health_monitor() {
    ui_header
    echo -e "${NEON_PINK}--- SYSTEM HEALTH MONITOR ---${RESET}"
    echo
    
    command -v certbot >/dev/null && success "Certbot: Installed" || error "Certbot: Missing"
    systemctl is-active cron >/dev/null 2>&1 && success "Cron: Active" || warning "Cron: Inactive"
    ping -c 1 google.com >/dev/null 2>&1 && success "Internet: Connected" || error "Internet: Disconnected"
    
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then warning "Port 80: IN USE"
    else success "Port 80: Available"
    fi

    detect_webserver
    if [[ ! -z "$WEBSERVER" ]]; then success "Webserver: $WEBSERVER (Active)"
    else warning "Webserver: None Detected"
    fi

    pause_screen
}

# =========================================================
# 6. AUTO REPAIR
# =========================================================
auto_repair() {
    ui_header
    echo -e "${NEON_PINK}--- SYSTEM AUTO REPAIR ---${RESET}"
    read -p "➜ Start automated system repair? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return

    echo
    progress_bar 25 "Repairing System Packages..."
    apt --fix-broken install -y >/dev/null 2>&1
    
    detect_webserver
    [[ ! -z "$WEBSERVER" ]] && systemctl restart $WEBSERVER
    
    certbot renew --dry-run >/dev/null 2>&1
    
    success "Auto repair completed successfully."
    log "REPAIR" "Auto repair completed"
    pause_screen
}

# =========================================================
# 7. AUTO RENEW
# =========================================================
setup_auto_renew() {
    ui_header
    echo -e "${NEON_PINK}--- SMART AUTO RENEW ---${RESET}"
    echo -e "This will automatically renew certs and sync files to panels."
    read -p "➜ Enable Auto-Renew? (y/n): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook \"/usr/local/bin/certmaster --sync\" >> $LOG_FILE 2>&1"
        crontab -l 2>/dev/null | grep -v "certmaster" | crontab -
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        success "Smart Auto-Renew is now Active."
        log "INFO" "Smart Auto-Renew Enabled"
    fi
    pause_screen
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
# 8. DASHBOARD
# =========================================================
dashboard() {
    ui_header
    TOTAL=$(find /etc/letsencrypt/live -maxdepth 1 -type d 2>/dev/null | wc -l)
    [[ $TOTAL -gt 0 ]] && TOTAL=$((TOTAL - 1))
    
    echo -e "${NEON_PINK}--- LIVE DASHBOARD ---${RESET}"
    echo
    echo -e "${CYAN}📦 Managed Certificates:${RESET} $TOTAL"
    echo -e "${CYAN}⚡ Software Version:${RESET}     v$VERSION"
    echo -e "${CYAN}📄 Log File Path:${RESET}        $LOG_FILE"
    pause_screen
}

# =========================================================
# 9. UPDATE SCRIPT
# =========================================================
update_script() {
    ui_header
    echo -e "${NEON_PINK}--- SOFTWARE UPDATE ---${RESET}"
    read -p "➜ Check and install latest update? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return

    echo
    progress_bar 20 "Connecting to GitHub..."
    HTTP_CODE=$(curl -H 'Cache-Control: no-cache' -s -w "%{http_code}" -o /tmp/certmaster_new.sh "$UPDATE_URL")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        mv /tmp/certmaster_new.sh /opt/CertMaster-Pro/certmaster.sh
        chmod +x /opt/CertMaster-Pro/certmaster.sh
        cp /opt/CertMaster-Pro/certmaster.sh /usr/local/bin/certmaster
        chmod +x /usr/local/bin/certmaster
        
        success "CertMaster updated successfully! Run 'certmaster' to see changes."
        exit 0
    else
        error "Update failed. GitHub returned HTTP Code: $HTTP_CODE"
    fi
    pause_screen
}

# =========================================================
# MAIN MENU
# =========================================================
main_menu() {
    while true; do
        ui_header
        echo -e "  ${NEON_GREEN}1)${RESET} Install New SSL Certificate"
        echo -e "  ${NEON_GREEN}2)${RESET} Wildcard SSL (Cloudflare)"
        echo -e "  ${NEON_GREEN}3)${RESET} List Managed Certificates"
        echo -e "  ${NEON_GREEN}4)${RESET} Delete / Wipe Certificate"
        echo -e "  ${NEON_GREEN}5)${RESET} System Health Monitor"
        echo -e "  ${NEON_GREEN}6)${RESET} Auto Repair System"
        echo -e "  ${NEON_GREEN}7)${RESET} Setup Smart Auto-Renew"
        echo -e "  ${NEON_GREEN}8)${RESET} Live Dashboard"
        echo -e "  ${NEON_GREEN}9)${RESET} Update Script"
        echo -e "  ${RED}0)${RESET} Exit"
        echo
        read -p "➜ Select Option [0-9]: " OPTION

        case $OPTION in
            1) install_certificate ;;
            2) wildcard_ssl ;;
            3) list_certificates ;;
            4) delete_certificate ;;
            5) health_monitor ;;
            6) auto_repair ;;
            7) setup_auto_renew ;;
            8) dashboard ;;
            9) update_script ;;
            0) clear; exit 0 ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

# =========================================================
# START
# =========================================================
main_menu
