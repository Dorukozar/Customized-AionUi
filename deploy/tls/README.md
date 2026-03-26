# TLS Setup — Diador Wildcard Certificate

## Prerequisites

1. **EC2 IAM Role** with these permissions on the diador.ai Route53 hosted zone:
   - `route53:ChangeResourceRecordSets` — creates the DNS-01 challenge TXT record
   - `route53:GetChange` — confirms DNS propagation (commonly omitted, causes silent failures)

2. **DNS**: `*.diador.ai` wildcard A record pointing to the EC2 public IP

## Initial Setup

```bash
# Run on the EC2 instance as root
sudo bash deploy/tls/setup-certbot.sh
```

This will:
- Install certbot + certbot-dns-route53 plugin
- Issue a wildcard cert for `*.diador.ai` and `diador.ai`
- Wait 120s for DNS propagation (double the default, avoids Route53 race)
- Verify the cert and run a renewal dry-run

## Auto-Renewal

```bash
# Install the cron job
sudo cp deploy/tls/renew-cron /etc/cron.d/diador-certbot-renew
sudo chmod 644 /etc/cron.d/diador-certbot-renew
```

The cron runs twice daily (2am + 2pm). Certbot only renews when the cert is within 30 days of expiry.

## Verification

```bash
# Check cert covers wildcard
openssl x509 -text -noout -in /etc/letsencrypt/live/diador.ai/cert.pem | grep DNS

# Test renewal without actually renewing
certbot renew --dry-run

# Check cert expiry date
openssl x509 -enddate -noout -in /etc/letsencrypt/live/diador.ai/cert.pem
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `DNS problem: NXDOMAIN` | Route53 propagation too slow | Increase `--dns-route53-propagation-seconds` to 180 |
| `PluginError` in certbot log | Missing IAM permission | Add `route53:GetChange` to the IAM policy |
| Cert not renewing via cron | Cron running as wrong user | Ensure cron file specifies `root` |
| Nginx still serving old cert | Missing post-hook | Verify `--post-hook "systemctl reload nginx"` in cron |
