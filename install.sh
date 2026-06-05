#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
   echo "❌ Please run as root:"
   echo "sudo bash install.sh"
   exit 1
fi

clear

echo "=================================================="
echo "         CertMaster-Pro Installer"
echo "=================================================="

echo
echo "📦 Installing dependencies..."

if command -v apt-get &> /dev/null; then

    apt-get update -qq

    apt-get install -y \
        jq \
        certbot \
        curl \
        lsof \
        openssl \
        cron

elif command -v yum &> /dev/null; then

    yum install -y epel-release

    yum install -y \
        jq \
        certbot \
        curl \
        lsof \
        openssl \
        cronie

else
    echo "Unsupported OS"
    exit 1
fi

systemctl enable cron 2>/dev/null
systemctl start cron 2>/dev/null

systemctl enable crond 2>/dev/null
systemctl start crond 2>/dev/null

INSTALL_DIR="/opt/CertMaster-Pro"

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/config"
mkdir -p "$INSTALL_DIR/logs"

cp certmaster.sh "$INSTALL_DIR/certmaster.sh"

chmod +x "$INSTALL_DIR/certmaster.sh"

ln -sf "$INSTALL_DIR/certmaster.sh" /usr/local/bin/certmaster

CONFIG_FILE="$INSTALL_DIR/config/settings.json"

if [ ! -f "$CONFIG_FILE" ]; then

cat > "$CONFIG_FILE" <<EOF
{
  "language": "en",
  "domains": []
}
EOF

fi

touch "$INSTALL_DIR/logs/activity.log"

clear

echo "=================================================="
echo "      CertMaster-Pro Installed Successfully"
echo "=================================================="

echo
echo "Run:"
echo
echo "certmaster"
echo
