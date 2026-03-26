#!/usr/bin/env bash
set -euo pipefail

# Diador — issue wildcard TLS cert via certbot DNS-01 + Route53
# Prerequisites:
#   - EC2 instance with IAM role that includes:
#     - route53:ChangeResourceRecordSets (on the diador.ai hosted zone)
#     - route53:GetChange (required for propagation confirmation)
#   - DNS: *.diador.ai wildcard A record → EC2 public IP

usage() {
  echo "Usage: $0"
  echo ""
  echo "Installs certbot + certbot-dns-route53 and issues a wildcard cert"
  echo "for *.diador.ai using DNS-01 challenge via Route53."
  echo ""
  echo "Prerequisites:"
  echo "  - EC2 IAM role with route53:ChangeResourceRecordSets + route53:GetChange"
  echo "  - *.diador.ai DNS A record pointing to this host"
  exit 1
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  usage
fi

echo "==> Installing certbot and Route53 plugin..."

# Install certbot via apt (snap also works but apt is simpler for automation)
if ! command -v certbot &>/dev/null; then
  apt-get update
  apt-get install -y certbot python3-certbot-dns-route53
  echo "  [+] certbot installed"
else
  echo "  [~] certbot already installed"
  # Ensure the Route53 plugin is present
  if ! pip3 show certbot-dns-route53 &>/dev/null 2>&1; then
    apt-get install -y python3-certbot-dns-route53
  fi
fi

echo ""
echo "==> Issuing wildcard cert for *.diador.ai..."
echo "    (DNS propagation wait: 120s to avoid Route53 race condition)"
echo ""

certbot certonly \
  --dns-route53 \
  --dns-route53-propagation-seconds 120 \
  -d "*.diador.ai" \
  -d "diador.ai" \
  --agree-tos \
  --non-interactive \
  --email "admin@diador.ai"

echo ""
echo "==> Verifying cert..."
openssl x509 -text -noout \
  -in /etc/letsencrypt/live/diador.ai/cert.pem \
  | grep -E "DNS:|Not After"

echo ""
echo "==> Testing renewal (dry run)..."
certbot renew --dry-run

echo ""
echo "======================================"
echo " Wildcard cert issued successfully!"
echo " Cert: /etc/letsencrypt/live/diador.ai/fullchain.pem"
echo " Key:  /etc/letsencrypt/live/diador.ai/privkey.pem"
echo ""
echo " Next: install the cron job for auto-renewal"
echo " See: deploy/tls/renew-cron"
echo "======================================"
