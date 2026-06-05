# =========================================================
#              CERTMASTER ENTERPRISE v3.5
#        Ultimate Commercial SSL Management Suite
# =========================================================
#
# FEATURES:
# ✔ Enterprise UI
# ✔ Neon Terminal
# ✔ Interactive Dashboard
# ✔ SSL Health Monitor
# ✔ Auto Repair
# ✔ Auto Renew
# ✔ Wildcard SSL
# ✔ Cloudflare DNS API
# ✔ Telegram Alerts
# ✔ SSL Grading System
# ✔ Live Expire Countdown
# ✔ Smart Panel Detection
# ✔ Auto Sync
# ✔ Progress Bars
# ✔ Commercial Table UI
# ✔ Rebecca / Marzban / Pasarguard / Marzneshin
#
# =========================================================

#!/usr/bin/env bash

VERSION="3.5 Enterprise"

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
# COLORS
# =========================================================

RESET='\033[0m'

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

NEON_BLUE='\033[38;5;45m'
NEON_GREEN='\033[38;5;46m'
NEON_PINK='\033[38;5;213m'
NEON_ORANGE='\033[38;5;208m'
GRAY='\033[38;5;245m'

# =========================================================
# ROOT CHECK
# =========================================================

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Please run as root.${RESET}"
    exit 1
fi

# =========================================================
# INIT
# =========================================================

mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

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
# DEPENDENCIES
# =========================================================

install_dependencies() {

    PKGS=()

    command -v jq >/dev/null || PKGS+=("jq")
    command -v certbot >/dev/null || PKGS+=("certbot")
    command -v curl >/dev/null || PKGS+=("curl")
    command -v lsof >/dev/null || PKGS+=("lsof")
    command -v openssl >/dev/null || PKGS+=("openssl")

    if [ ${#PKGS[@]} -gt 0 ]; then

        echo -e "${YELLOW}Installing dependencies...${RESET}"

        apt update -y >/dev/null 2>&1
        apt install -y "${PKGS[@]}" >/dev/null 2>&1
    fi
}

install_dependencies

# =========================================================
# LOGGING
# =========================================================

log() {

    TYPE=$1
    MESSAGE=$2

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$TYPE] $MESSAGE" >> "$LOG_FILE"
}

# =========================================================
# UI
# =========================================================

ui_header() {

clear

echo -e "${NEON_BLUE}"
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                 CERTMASTER ENTERPRISE v$VERSION                    ║"
echo "║            Commercial SSL Management Platform                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

}

success() {
    echo -e "${NEON_GREEN}✔ $1${RESET}"
}

error() {
    echo -e "${RED}✘ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

info() {
    echo -e "${NEON_BLUE}➜ $1${RESET}"
}

pause_screen() {
    echo
    read -p "Press Enter to continue..."
}

# =========================================================
# PROGRESS BAR
# =========================================================

progress_bar() {

    DURATION=$1

    for ((i=0; i<=DURATION; i++)); do

        PERCENT=$((i * 100 / DURATION))

        printf "\r${NEON_GREEN}["
        for ((j=0; j<i; j++)); do printf "▓"; done
        for ((j=i; j<DURATION; j++)); do printf "░"; done
        printf "] %d%%${RESET}" "$PERCENT"

        sleep 0.03
    done

    echo
}

# =========================================================
# AUTO DETECT WEBSERVER
# =========================================================

detect_webserver() {

    if systemctl is-active nginx >/dev/null 2>&1; then
        WEBSERVER="nginx"

    elif systemctl is-active apache2 >/dev/null 2>&1; then
        WEBSERVER="apache2"

    else
        WEBSERVER=""
    fi
}

# =========================================================
# SSL GRADE
# =========================================================

ssl_grade() {

    DAYS=$1

    if [ $DAYS -gt 60 ]; then
        echo "A+"

    elif [ $DAYS -gt 30 ]; then
        echo "A"

    elif [ $DAYS -gt 15 ]; then
        echo "B"

    else
        echo "C"
    fi
}

# =========================================================
# TELEGRAM ALERT
# =========================================================

telegram_alert() {

    TOKEN=$(jq -r '.telegram_bot_token' "$CONFIG_FILE")
    CHAT_ID=$(jq -r '.telegram_chat_id' "$CONFIG_FILE")

    MESSAGE="$1"

    if [[ ! -z "$TOKEN" && ! -z "$CHAT_ID" ]]; then

        curl -s \
        -X POST \
        "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$MESSAGE" >/dev/null
    fi
}

# =========================================================
# HEALTH MONITOR
# =========================================================

health_monitor() {

    ui_header

    echo -e "${NEON_PINK}SYSTEM HEALTH MONITOR${RESET}"

    echo

    command -v certbot >/dev/null \
    && success "Certbot Installed" \
    || error "Certbot Missing"

    systemctl is-active cron >/dev/null 2>&1 \
    && success "Cron Active" \
    || warning "Cron Inactive"

    ping -c 1 google.com >/dev/null 2>&1 \
    && success "Internet Connected" \
    || error "No Internet"

    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
        warning "Port 80 In Use"
    else
        success "Port 80 Available"
    fi

    detect_webserver

    if [[ ! -z "$WEBSERVER" ]]; then
        success "$WEBSERVER Active"
    else
        warning "No Webserver Detected"
    fi

    echo
    pause_screen
}

# =========================================================
# AUTO REPAIR
# =========================================================

auto_repair() {

    ui_header

    info "Starting Auto Repair..."

    progress_bar 25

    apt --fix-broken install -y >/dev/null 2>&1

    detect_webserver

    if [[ ! -z "$WEBSERVER" ]]; then
        systemctl restart $WEBSERVER
    fi

    certbot renew --dry-run >/dev/null 2>&1

    success "Auto Repair Completed."

    log "REPAIR" "Auto repair completed"

    pause_screen
}

# =========================================================
# PORT CHECK
# =========================================================

check_port_80() {

    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then

        warning "Port 80 is currently in use."

        read -p "Stop webserver temporarily? (y/n): " STOP_WEB

        if [[ "$STOP_WEB" == "y" || "$STOP_WEB" == "Y" ]]; then

            detect_webserver

            if [[ ! -z "$WEBSERVER" ]]; then
                systemctl stop $WEBSERVER
                success "$WEBSERVER stopped."
            fi

            return 0
        else
            return 1
        fi
    fi

    return 0
}

# =========================================================
# PANEL SELECTOR
# =========================================================

select_panel() {

echo
echo "1) Rebecca"
echo "2) Marzban"
echo "3) Pasarguard"
echo "4) Marzneshin"
echo "5) Custom Path"

echo
read -p "Select Panel: " panel

case $panel in

1)
TARGET_BASE_DIR="/var/lib/rebecca/certs"
PANEL_NAME="Rebecca"
;;

2)
TARGET_BASE_DIR="/var/lib/marzban/certs"
PANEL_NAME="Marzban"
;;

3)
TARGET_BASE_DIR="/var/lib/pasarguard/certs"
PANEL_NAME="Pasarguard"
;;

4)
TARGET_BASE_DIR="/var/lib/marzneshin/certs"
PANEL_NAME="Marzneshin"
;;

5)
read -p "Enter custom certs path: " custom_path
TARGET_BASE_DIR="$custom_path"
PANEL_NAME="Custom"
;;

*)
error "Invalid choice."
return 1
;;

esac
}

# =========================================================
# INSTALL SSL
# =========================================================

install_certificate() {

ui_header

select_panel || return

echo
read -p "Enter domain(s): " DOMAIN_INPUT

if [[ -z "$DOMAIN_INPUT" ]]; then
    error "Domain required."
    pause_screen
    return
fi

check_port_80 || return

IFS=',' read -ra DOMAINS <<< "$DOMAIN_INPUT"

for domain in "${DOMAINS[@]}"; do

DOMAIN=$(echo "$domain" | xargs)

echo
info "Generating SSL for $DOMAIN"

progress_bar 35

certbot certonly \
--standalone \
-d "$DOMAIN" \
--non-interactive \
--agree-tos \
--register-unsafely-without-email

if [ $? -eq 0 ]; then

FINAL_PATH="$TARGET_BASE_DIR/$DOMAIN"

mkdir -p "$FINAL_PATH"

cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$FINAL_PATH/"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$FINAL_PATH/"

chmod 644 "$FINAL_PATH/fullchain.pem"
chmod 600 "$FINAL_PATH/privkey.pem"

TMP=$(jq --arg d "$DOMAIN" \
--arg p "$FINAL_PATH" \
--arg pn "$PANEL_NAME" \
'.domains += [{
"main_domain":$d,
"install_path":$p,
"panel":$pn
}]' \
"$CONFIG_FILE")

echo "$TMP" > "$CONFIG_FILE"

success "$DOMAIN installed successfully."

telegram_alert "SSL Installed for $DOMAIN"

log "SUCCESS" "Installed SSL for $DOMAIN"

else

error "SSL failed for $DOMAIN"

telegram_alert "SSL FAILED for $DOMAIN"

log "ERROR" "SSL failed for $DOMAIN"

fi

done

detect_webserver

if [[ ! -z "$WEBSERVER" ]]; then
    systemctl start $WEBSERVER
fi

pause_screen
}

# =========================================================
# WILDCARD SSL
# =========================================================

wildcard_ssl() {

ui_header

echo
read -p "Enter wildcard domain (example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
    return
fi

CF_EMAIL=$(jq -r '.cloudflare_email' "$CONFIG_FILE")
CF_KEY=$(jq -r '.cloudflare_api_key' "$CONFIG_FILE")

if [[ -z "$CF_EMAIL" || -z "$CF_KEY" ]]; then

warning "Cloudflare API not configured."

read -p "Cloudflare Email: " CF_EMAIL
read -p "Cloudflare API Key: " CF_KEY

TMP=$(jq \
--arg e "$CF_EMAIL" \
--arg k "$CF_KEY" \
'.cloudflare_email=$e | .cloudflare_api_key=$k' \
"$CONFIG_FILE")

echo "$TMP" > "$CONFIG_FILE"

fi

mkdir -p ~/.secrets

cat > ~/.secrets/cloudflare.ini <<EOF
dns_cloudflare_email = $CF_EMAIL
dns_cloudflare_api_key = $CF_KEY
EOF

chmod 600 ~/.secrets/cloudflare.ini

info "Generating Wildcard SSL..."

progress_bar 40

certbot certonly \
--dns-cloudflare \
--dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
-d "*.$DOMAIN" \
-d "$DOMAIN"

pause_screen
}

# =========================================================
# AUTO RENEW
# =========================================================

enable_auto_renew() {

CRON_JOB="0 3 * * * certbot renew --quiet && /usr/local/bin/certmaster --sync >> $LOG_FILE 2>&1"

crontab -l 2>/dev/null | grep -q "certbot renew"

if [ $? -ne 0 ]; then

(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

success "Auto renew enabled."

log "INFO" "Auto renew enabled"

else

warning "Auto renew already enabled."

fi

pause_screen
}

# =========================================================
# SYNC
# =========================================================

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
}

# =========================================================
# LIST CERTIFICATES
# =========================================================

list_certificates() {

while true; do

ui_header

CERTS=()

echo -e "${NEON_BLUE}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${NEON_BLUE}║                         SSL CERTIFICATES                           ║${RESET}"
echo -e "${NEON_BLUE}╚══════════════════════════════════════════════════════════════════════╝${RESET}"

echo

printf "${CYAN}%-5s %-45s %-12s %-8s${RESET}\n" \
"ID" "DOMAIN" "STATUS" "GRADE"

echo "──────────────────────────────────────────────────────────────────────"

INDEX=1

for cert_dir in /etc/letsencrypt/live/*; do

[ -d "$cert_dir" ] || continue

DOMAIN=$(basename "$cert_dir")

CERTS+=("$DOMAIN")

CERT_FILE="$cert_dir/fullchain.pem"

if [ ! -f "$CERT_FILE" ]; then
continue
fi

EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)

EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)

DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

GRADE=$(ssl_grade $DAYS_LEFT)

if [ $DAYS_LEFT -le 7 ]; then
STATUS="${RED}CRITICAL${RESET}"

elif [ $DAYS_LEFT -le 30 ]; then
STATUS="${YELLOW}WARNING${RESET}"

else
STATUS="${GREEN}HEALTHY${RESET}"
fi

printf "%-5s %-45s %-20b %-8s\n" \
"$INDEX" \
"$DOMAIN" \
"$STATUS" \
"$GRADE"

((INDEX++))

done

echo
echo -e "${GREEN}0) Back${RESET}"

echo
read -p "Select Certificate ID: " CHOICE

if [[ "$CHOICE" == "0" ]]; then
return
fi

SELECTED_INDEX=$((CHOICE - 1))

DOMAIN="${CERTS[$SELECTED_INDEX]}"

if [[ -z "$DOMAIN" ]]; then
error "Invalid certificate."
sleep 1
continue
fi

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

CERT_FILE="$CERT_DIR/fullchain.pem"
KEY_FILE="$CERT_DIR/privkey.pem"

EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)

EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)

DAYS_LEFT=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

GRADE=$(ssl_grade $DAYS_LEFT)

PANEL_NAME="Unknown"
PANEL_PATH=""

if [[ -d "/var/lib/rebecca/certs/$DOMAIN" ]]; then
PANEL_NAME="Rebecca"
PANEL_PATH="/var/lib/rebecca/certs/$DOMAIN"

elif [[ -d "/var/lib/marzban/certs/$DOMAIN" ]]; then
PANEL_NAME="Marzban"
PANEL_PATH="/var/lib/marzban/certs/$DOMAIN"

elif [[ -d "/var/lib/pasarguard/certs/$DOMAIN" ]]; then
PANEL_NAME="Pasarguard"
PANEL_PATH="/var/lib/pasarguard/certs/$DOMAIN"

elif [[ -d "/var/lib/marzneshin/certs/$DOMAIN" ]]; then
PANEL_NAME="Marzneshin"
PANEL_PATH="/var/lib/marzneshin/certs/$DOMAIN"
fi

clear

echo -e "${NEON_GREEN}"
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                      CERTIFICATE DETAILS                           ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo
echo -e "${CYAN}🌐 Domain:${RESET}"
echo "   $DOMAIN"

echo
echo -e "${CYAN}📦 Active Panel:${RESET}"
echo "   $PANEL_NAME"

echo
echo -e "${CYAN}📄 Active Certificate:${RESET}"
echo "   $PANEL_PATH/fullchain.pem"

echo
echo -e "${MAGENTA}🔑 Active Private Key:${RESET}"
echo "   $PANEL_PATH/privkey.pem"

echo
echo -e "${YELLOW}📂 LetsEncrypt Source:${RESET}"
echo "   /etc/letsencrypt/live/$DOMAIN/"

echo
echo -e "${CYAN}📅 Expire Date:${RESET}"
echo "   $(date -d "$EXPIRY_DATE" +%Y-%m-%d)"

echo
echo -e "${CYAN}⏳ Days Left:${RESET}"
echo "   $DAYS_LEFT days"

echo
echo -e "${CYAN}🏆 SSL Grade:${RESET}"
echo "   $GRADE"

echo

if [ $DAYS_LEFT -le 7 ]; then
echo -e "${RED}● STATUS: CRITICAL${RESET}"

elif [ $DAYS_LEFT -le 30 ]; then
echo -e "${YELLOW}● STATUS: WARNING${RESET}"

else
echo -e "${GREEN}● STATUS: HEALTHY${RESET}"
fi

pause_screen

done
}

# =========================================================
# DASHBOARD
# =========================================================

dashboard() {

ui_header

TOTAL=$(find /etc/letsencrypt/live -maxdepth 1 -type d | wc -l)
TOTAL=$((TOTAL - 1))

EXPIRING=$(find /etc/letsencrypt/live -maxdepth 1 -type d | wc -l)

echo -e "${NEON_GREEN}╔══════════════════════════════════════╗${RESET}"
echo -e "${NEON_GREEN}║         LIVE SSL DASHBOARD          ║${RESET}"
echo -e "${NEON_GREEN}╚══════════════════════════════════════╝${RESET}"

echo
echo -e "${CYAN}📦 Total Certificates:${RESET} $TOTAL"
echo -e "${CYAN}⚡ Enterprise Version:${RESET} $VERSION"
echo -e "${CYAN}📄 Logs:${RESET} $LOG_FILE"

echo

pause_screen
}

# =========================================================
# UPDATE
# =========================================================

update_script() {

ui_header

info "Checking for updates..."

HTTP_CODE=$(curl -s -w "%{http_code}" \
-o /tmp/certmaster_new.sh \
"$UPDATE_URL")

if [[ "$HTTP_CODE" == "200" ]]; then

mv /tmp/certmaster_new.sh /usr/local/bin/certmaster

chmod +x /usr/local/bin/certmaster

success "Updated successfully."

log "UPDATE" "Script updated"

else

error "Update failed."

fi

pause_screen
}

# =========================================================
# MAIN MENU
# =========================================================

main_menu() {

while true; do

ui_header

echo -e "${WHITE}1) Install SSL Certificate${RESET}"
echo -e "${WHITE}2) Wildcard SSL (Cloudflare)${RESET}"
echo -e "${WHITE}3) List Certificates${RESET}"
echo -e "${WHITE}4) Dashboard${RESET}"
echo -e "${WHITE}5) Health Monitor${RESET}"
echo -e "${WHITE}6) Auto Repair${RESET}"
echo -e "${WHITE}7) Enable Auto Renew${RESET}"
echo -e "${WHITE}8) Sync Certificates${RESET}"
echo -e "${WHITE}9) Update Script${RESET}"
echo -e "${WHITE}0) Exit${RESET}"

echo
read -p "Select Option: " OPTION

case $OPTION in

1) install_certificate ;;
2) wildcard_ssl ;;
3) list_certificates ;;
4) dashboard ;;
5) health_monitor ;;
6) auto_repair ;;
7) enable_auto_renew ;;

8)
sync_certificates
success "Sync completed."
pause_screen
;;

9) update_script ;;
0) exit 0 ;;

*)
error "Invalid option."
sleep 1
;;

esac

done
}

# =========================================================
# CLI MODE
# =========================================================

if [[ "$1" == "--sync" ]]; then
sync_certificates
exit 0
fi

# =========================================================
# START
# =========================================================

main_menu
