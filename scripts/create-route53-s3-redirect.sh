#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# Create an HTTPS-capable domain redirect using:
#   Route 53 → CloudFront → S3 website-redirect bucket
#
# Fully idempotent - safe to re-run at any point after a partial
# failure.  Each resource is checked before creation.
#
# Usage:
#   bash create-route53-s3-redirect.sh <source-domain> <target-domain> [aws-profile]
#
# Example:
#   bash create-route53-s3-redirect.sh old.example.com new.example.com
#
# Environment variables (all optional):
#   AWS_REGION          - S3 bucket region           (default: us-east-1)
#   REDIRECT_PROTOCOL   - http or https              (default: https)
#   ROUTE53_ZONE_NAME   - force a specific hosted-zone name
#   PRICE_CLASS         - CloudFront price class      (default: PriceClass_100)
#   DRY_RUN             - set to "true" to print plan and exit
#
# Prerequisites:
#   - AWS CLI v2
#   - Permissions: s3, acm, cloudfront, route53
#   - A Route 53 public hosted zone that covers the source domain
#
# Notes:
#   - ACM certificates for CloudFront MUST live in us-east-1.
#   - The S3 bucket is named after the source domain (required for
#     S3 website hosting).
#   - CloudFront uses the S3 website endpoint as a custom HTTP origin
#     (not an S3 REST origin - this is intentional so the redirect
#     rules work).
# -------------------------------------------------------------

readonly SCRIPT_NAME="$(basename "$0")"

# ── Helpers ───────────────────────────────────────────────────

log()   { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
err()   { log "ERROR: $*" >&2; }
die()   { err "$@"; exit 1; }

cleanup() {
  local f
  for f in "${_tmpfiles[@]:-}"; do
    rm -f "$f" 2>/dev/null || true
  done
}
trap cleanup EXIT
_tmpfiles=()

mktmp() {
  local f
  f="$(mktemp)"
  _tmpfiles+=("$f")
  echo "$f"
}

aws_cmd() {
  aws --profile "$PROFILE" "$@"
}

# ── Arguments & validation ────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo "Usage: $SCRIPT_NAME <source-domain> <target-domain> [aws-profile]"
  exit 1
fi

SOURCE_DOMAIN="${1%.}"
TARGET_DOMAIN="${2%.}"
PROFILE="${3:-admin}"
REGION="${AWS_REGION:-us-east-1}"
REDIRECT_PROTOCOL="${REDIRECT_PROTOCOL:-https}"
PRICE_CLASS="${PRICE_CLASS:-PriceClass_100}"
DRY_RUN="${DRY_RUN:-false}"
readonly ACM_REGION="us-east-1"
readonly CLOUDFRONT_HOSTED_ZONE_ID="Z2FDTNDATAQYW2"   # AWS-global constant

[[ "$SOURCE_DOMAIN" != "$TARGET_DOMAIN" ]] \
  || die "Source and target domains must differ."

[[ "$REDIRECT_PROTOCOL" == "http" || "$REDIRECT_PROTOCOL" == "https" ]] \
  || die "REDIRECT_PROTOCOL must be 'http' or 'https'."

# Quick credential / connectivity check
aws_cmd sts get-caller-identity --output text >/dev/null 2>&1 \
  || die "AWS credentials are not configured or expired for profile '$PROFILE'."

# ── Locate hosted zone ────────────────────────────────────────

find_hosted_zone() {
  local domain="$1"
  local override="${ROUTE53_ZONE_NAME:-}"
  local candidate zone_name zone_id

  if [[ -n "$override" ]]; then
    candidate="${override%.}"
    zone_name="$(aws_cmd route53 list-hosted-zones-by-name \
      --dns-name "$candidate" --max-items 1 \
      --query 'HostedZones[0].Name' --output text)"
    if [[ "$zone_name" == "${candidate}." ]]; then
      zone_id="$(aws_cmd route53 list-hosted-zones-by-name \
        --dns-name "$candidate" --max-items 1 \
        --query 'HostedZones[0].Id' --output text)"
      echo "${zone_id##*/}"
      return 0
    fi
    die "ROUTE53_ZONE_NAME '$override' not found in this account."
  fi

  candidate="$domain"
  while [[ "$candidate" == *.* ]]; do
    zone_name="$(aws_cmd route53 list-hosted-zones-by-name \
      --dns-name "$candidate" --max-items 1 \
      --query 'HostedZones[0].Name' --output text)"
    if [[ "$zone_name" == "${candidate}." ]]; then
      zone_id="$(aws_cmd route53 list-hosted-zones-by-name \
        --dns-name "$candidate" --max-items 1 \
        --query 'HostedZones[0].Id' --output text)"
      echo "${zone_id##*/}"
      return 0
    fi
    local remainder="${candidate#*.}"
    [[ "$remainder" != "$candidate" ]] || break
    candidate="$remainder"
  done

  return 1
}

HOSTED_ZONE_ID="$(find_hosted_zone "$SOURCE_DOMAIN")" \
  || die "No matching Route 53 hosted zone for '$SOURCE_DOMAIN'."

S3_WEBSITE_ENDPOINT="${SOURCE_DOMAIN}.s3-website-${REGION}.amazonaws.com"

# ── Plan summary ──────────────────────────────────────────────

log "==========================================="
log "  Source domain:     $SOURCE_DOMAIN"
log "  Target domain:     $TARGET_DOMAIN"
log "  Redirect protocol: $REDIRECT_PROTOCOL"
log "  S3 bucket region:  $REGION"
log "  ACM region:        $ACM_REGION"
log "  Price class:       $PRICE_CLASS"
log "  AWS profile:       $PROFILE"
log "  Hosted zone ID:    $HOSTED_ZONE_ID"
log "==========================================="

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY_RUN=true - exiting before making changes."
  exit 0
fi

# ── 1. S3 redirect bucket ────────────────────────────────────

log "Step 1/5: S3 redirect bucket"

if aws_cmd s3api head-bucket --bucket "$SOURCE_DOMAIN" --region "$REGION" 2>/dev/null; then
  log "  Bucket '$SOURCE_DOMAIN' already exists - skipping create."
else
  log "  Creating bucket '$SOURCE_DOMAIN' in $REGION..."
  if [[ "$REGION" == "us-east-1" ]]; then
    aws_cmd s3api create-bucket \
      --bucket "$SOURCE_DOMAIN" \
      --region "$REGION"
  else
    aws_cmd s3api create-bucket \
      --bucket "$SOURCE_DOMAIN" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi

log "  Configuring website redirect → ${REDIRECT_PROTOCOL}://${TARGET_DOMAIN}"
aws_cmd s3api put-bucket-website \
  --bucket "$SOURCE_DOMAIN" \
  --region "$REGION" \
  --website-configuration "{
    \"RedirectAllRequestsTo\": {
      \"HostName\": \"${TARGET_DOMAIN}\",
      \"Protocol\": \"${REDIRECT_PROTOCOL}\"
    }
  }"

# Block all public access - CloudFront uses the website endpoint
# over HTTP (origin-protocol http-only) so no public bucket policy
# is needed.  Belt-and-suspenders.
aws_cmd s3api put-public-access-block \
  --bucket "$SOURCE_DOMAIN" \
  --region "$REGION" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  2>/dev/null || true   # fails if bucket predates this feature; non-critical

# ── 2. ACM certificate ───────────────────────────────────────

log "Step 2/5: ACM certificate in $ACM_REGION"

CERT_ARN="$(aws_cmd acm list-certificates \
  --region "$ACM_REGION" \
  --certificate-statuses ISSUED PENDING_VALIDATION \
  --query "CertificateSummaryList[?DomainName=='${SOURCE_DOMAIN}'].CertificateArn | [0]" \
  --output text)"

if [[ -z "$CERT_ARN" || "$CERT_ARN" == "None" ]]; then
  log "  Requesting new certificate for ${SOURCE_DOMAIN}..."
  CERT_ARN="$(aws_cmd acm request-certificate \
    --region "$ACM_REGION" \
    --domain-name "$SOURCE_DOMAIN" \
    --validation-method DNS \
    --query 'CertificateArn' \
    --output text)"
  log "  Certificate ARN: $CERT_ARN"
else
  log "  Found existing certificate: $CERT_ARN"
fi

# ── 3. ACM DNS validation ────────────────────────────────────

log "Step 3/5: ACM DNS validation"

CERT_STATUS="$(aws_cmd acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --region "$ACM_REGION" \
  --query 'Certificate.Status' \
  --output text)"

if [[ "$CERT_STATUS" == "ISSUED" ]]; then
  log "  Certificate already issued - skipping validation."
else
  log "  Waiting for validation resource record from ACM..."
  VALIDATION_NAME="None"
  VALIDATION_TYPE="None"
  VALIDATION_VALUE="None"

  for attempt in $(seq 1 12); do
    VALIDATION_NAME="$(aws_cmd acm describe-certificate \
      --certificate-arn "$CERT_ARN" --region "$ACM_REGION" \
      --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' \
      --output text)"
    VALIDATION_TYPE="$(aws_cmd acm describe-certificate \
      --certificate-arn "$CERT_ARN" --region "$ACM_REGION" \
      --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Type' \
      --output text)"
    VALIDATION_VALUE="$(aws_cmd acm describe-certificate \
      --certificate-arn "$CERT_ARN" --region "$ACM_REGION" \
      --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' \
      --output text)"

    if [[ "$VALIDATION_NAME" != "None" && "$VALIDATION_TYPE" != "None" && "$VALIDATION_VALUE" != "None" ]]; then
      break
    fi
    log "  Attempt $attempt/12 - validation record not ready, waiting 10s..."
    sleep 10
  done

  [[ "$VALIDATION_NAME" != "None" && "$VALIDATION_TYPE" != "None" && "$VALIDATION_VALUE" != "None" ]] \
    || die "ACM validation record not available after 2 minutes. Re-run the script."

  log "  Upserting validation record: $VALIDATION_NAME → $VALIDATION_VALUE"

  BATCH="$(mktmp)"
  cat > "$BATCH" <<ENDJSON
{
  "Comment": "ACM validation for ${SOURCE_DOMAIN}",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "${VALIDATION_NAME}",
      "Type": "${VALIDATION_TYPE}",
      "TTL": 300,
      "ResourceRecords": [{"Value": "${VALIDATION_VALUE}"}]
    }
  }]
}
ENDJSON

  aws_cmd route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "file://$BATCH" >/dev/null

  log "  Waiting for certificate to validate (this may take a few minutes)..."
  aws_cmd acm wait certificate-validated \
    --certificate-arn "$CERT_ARN" \
    --region "$ACM_REGION"
  log "  Certificate validated."
fi

# ── 4. CloudFront distribution ────────────────────────────────

log "Step 4/5: CloudFront distribution"

DIST_ID="$(aws_cmd cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Quantity > \`0\` && contains(Aliases.Items, '${SOURCE_DOMAIN}')].Id | [0]" \
  --output text 2>/dev/null || echo "None")"

if [[ -n "$DIST_ID" && "$DIST_ID" != "None" ]]; then
  CLOUDFRONT_DOMAIN="$(aws_cmd cloudfront get-distribution \
    --id "$DIST_ID" \
    --query 'Distribution.DomainName' \
    --output text)"
  log "  Using existing distribution: $DIST_ID ($CLOUDFRONT_DOMAIN)"
else
  log "  Creating new distribution..."

  CALLER_REF="${SOURCE_DOMAIN}-redirect-$(date +%s)"
  DIST_CONFIG="$(mktmp)"
  cat > "$DIST_CONFIG" <<ENDJSON
{
  "CallerReference": "${CALLER_REF}",
  "Comment": "Redirect ${SOURCE_DOMAIN} → ${REDIRECT_PROTOCOL}://${TARGET_DOMAIN}",
  "Aliases": {
    "Quantity": 1,
    "Items": ["${SOURCE_DOMAIN}"]
  },
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3Website-${SOURCE_DOMAIN}",
      "DomainName": "${S3_WEBSITE_ENDPOINT}",
      "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "http-only",
        "OriginSslProtocols": { "Quantity": 1, "Items": ["TLSv1.2"] },
        "OriginReadTimeout": 30,
        "OriginKeepaliveTimeout": 5
      }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3Website-${SOURCE_DOMAIN}",
    "ViewerProtocolPolicy": "allow-all",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    },
    "Compress": false,
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  },
  "PriceClass": "${PRICE_CLASS}",
  "Enabled": true,
  "ViewerCertificate": {
    "ACMCertificateArn": "${CERT_ARN}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "Restrictions": {
    "GeoRestriction": { "RestrictionType": "none", "Quantity": 0 }
  },
  "HttpVersion": "http2and3",
  "IsIPV6Enabled": true
}
ENDJSON

  DIST_ID="$(aws_cmd cloudfront create-distribution \
    --distribution-config "file://${DIST_CONFIG}" \
    --query 'Distribution.Id' \
    --output text)"

  CLOUDFRONT_DOMAIN="$(aws_cmd cloudfront get-distribution \
    --id "$DIST_ID" \
    --query 'Distribution.DomainName' \
    --output text)"

  log "  Created distribution: $DIST_ID ($CLOUDFRONT_DOMAIN)"
fi

# ── 5. Route 53 alias records ─────────────────────────────────

log "Step 5/5: Route 53 alias records (A + AAAA)"

BATCH="$(mktmp)"
cat > "$BATCH" <<ENDJSON
{
  "Comment": "Alias ${SOURCE_DOMAIN} → CloudFront ${DIST_ID}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${SOURCE_DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${CLOUDFRONT_HOSTED_ZONE_ID}",
          "DNSName": "${CLOUDFRONT_DOMAIN}",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${SOURCE_DOMAIN}",
        "Type": "AAAA",
        "AliasTarget": {
          "HostedZoneId": "${CLOUDFRONT_HOSTED_ZONE_ID}",
          "DNSName": "${CLOUDFRONT_DOMAIN}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
ENDJSON

aws_cmd route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "file://$BATCH" >/dev/null

# ── Done ──────────────────────────────────────────────────────

log "==========================================="
log "  Redirect created successfully"
log "  ${SOURCE_DOMAIN} → ${REDIRECT_PROTOCOL}://${TARGET_DOMAIN}"
log ""
log "  CloudFront distribution: $DIST_ID"
log "  CloudFront domain:       $CLOUDFRONT_DOMAIN"
log "==========================================="
log ""
log "Notes:"
log "  - CloudFront deployment can take 5-15 minutes after creation."
log "  - S3 handles path + query string forwarding automatically."
log "  - Re-running this script is safe (all steps are idempotent)."
