#!/usr/bin/env bash

echo "Removing CertMaster-Pro..."

rm -rf /opt/CertMaster-Pro

rm -f /usr/local/bin/certmaster

crontab -l 2>/dev/null | grep -v "certbot renew" | crontab -

echo "Done."
