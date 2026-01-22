#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# Add CloudFront in front of an existing S3 bucket
#
# Usage:
#   bash add-s3-cloudfront.sh <bucket-name> [profile-name]
#     [--public-path <path>]...
#
# Example:
#   bash add-s3-cloudfront.sh my-bucket admin \
#     --public-path tutorials \
#     --public-path publicuploads
# -------------------------------------------------------------

# Ensure jq available
JQ_CMD=$(command -v jq 2>/dev/null || echo "/usr/bin/jq" || echo "/usr/local/bin/jq")
if [[ ! -x "$JQ_CMD" ]]; then
  echo "Error: jq command not found. Please install jq."
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <bucket-name> [profile-name] [--public-path <path>]"
  exit 1
fi

BUCKET="$1"
PROFILE="${2:-admin}"
shift || true
shift || true

PUBLIC_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-path)
      PUBLIC_PATHS+=("$2")
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity \
  --profile "$PROFILE" \
  --query Account \
  --output text)

echo "========================================="
echo "🪣 Bucket: $BUCKET"
echo "👔 Profile: $PROFILE"
echo "🌐 Public CloudFront paths: ${PUBLIC_PATHS[*]:-(none)}"
echo "========================================="

# -------------------------------------------------------------
# 1. Create or retrieve Origin Access Control
# -------------------------------------------------------------
OAC_NAME="${BUCKET}-oac"
echo "Checking for existing Origin Access Control: ${OAC_NAME}..."

# Try to find existing OAC
EXISTING_OAC=$(aws cloudfront list-origin-access-controls \
  --profile "$PROFILE" \
  --query "OriginAccessControlList.Items[?Name=='${OAC_NAME}'].Id | [0]" \
  --output text 2>/dev/null || echo "None")

if [[ "$EXISTING_OAC" != "None" && -n "$EXISTING_OAC" ]]; then
  echo "✓ Found existing OAC: ${EXISTING_OAC}"
  OAC_ID="$EXISTING_OAC"
else
  echo "Creating new Origin Access Control..."
  OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config "{
      \"Name\": \"${OAC_NAME}\",
      \"Description\": \"OAC for ${BUCKET}\",
      \"SigningProtocol\": \"sigv4\",
      \"SigningBehavior\": \"always\",
      \"OriginAccessControlOriginType\": \"s3\"
    }" \
    --profile "$PROFILE" \
    --query "OriginAccessControl.Id" \
    --output text)
  echo "✓ Created OAC: ${OAC_ID}"
fi

# -------------------------------------------------------------
# 2. Create or retrieve cache policy for presigned URLs
# -------------------------------------------------------------
CACHE_POLICY_NAME="${BUCKET}-presigned-cache"
echo "Checking for existing cache policy: ${CACHE_POLICY_NAME}..."

EXISTING_POLICY=$(aws cloudfront list-cache-policies \
  --profile "$PROFILE" \
  --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='${CACHE_POLICY_NAME}'].CachePolicy.Id | [0]" \
  --output text 2>/dev/null || echo "None")

if [[ "$EXISTING_POLICY" != "None" && -n "$EXISTING_POLICY" ]]; then
  echo "✓ Found existing cache policy: ${EXISTING_POLICY}"
  CACHE_POLICY_ID="$EXISTING_POLICY"
else
  echo "Creating cache policy for presigned URLs..."
  CACHE_POLICY_ID=$(aws cloudfront create-cache-policy \
    --cache-policy-config "{
      \"Name\": \"${CACHE_POLICY_NAME}\",
      \"Comment\": \"Low-TTL cache for presigned URLs and COG imagery\",
      \"MinTTL\": 0,
      \"DefaultTTL\": 300,
      \"MaxTTL\": 3600,
      \"ParametersInCacheKeyAndForwardedToOrigin\": {
        \"EnableAcceptEncodingGzip\": false,
        \"EnableAcceptEncodingBrotli\": false,
        \"QueryStringsConfig\": {
          \"QueryStringBehavior\": \"all\"
        },
        \"HeadersConfig\": {
          \"HeaderBehavior\": \"whitelist\",
          \"Headers\": {
            \"Quantity\": 3,
            \"Items\": [\"Origin\", \"Access-Control-Request-Method\", \"Access-Control-Request-Headers\"]
          }
        },
        \"CookiesConfig\": {
          \"CookieBehavior\": \"none\"
        }
      }
    }" \
    --profile "$PROFILE" \
    --query "CachePolicy.Id" \
    --output text)
  echo "✓ Created cache policy: ${CACHE_POLICY_ID}"
fi

# -------------------------------------------------------------
# 3. Build CloudFront behaviors
# -------------------------------------------------------------

DEFAULT_BEHAVIOR=$(cat <<EOF
{
  "TargetOriginId": "S3-${BUCKET}",
  "ViewerProtocolPolicy": "redirect-to-https",
  "AllowedMethods": {
    "Quantity": 3,
    "Items": ["GET", "HEAD", "OPTIONS"],
    "CachedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    }
  },
  "CachePolicyId": "${CACHE_POLICY_ID}",
  "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
  "Compress": false
}
EOF
)

if [[ ${#PUBLIC_PATHS[@]} -gt 0 ]]; then
  PATHS_JSON=$(printf '%s\n' "${PUBLIC_PATHS[@]}" | "$JQ_CMD" -R . | "$JQ_CMD" -s .)

  ORDERED_BEHAVIORS=$(
    "$JQ_CMD" -n \
      --arg bucket "$BUCKET" \
      --argjson paths "$PATHS_JSON" \
      '{
        Quantity: ($paths | length),
        Items: [
          $paths[] | {
            PathPattern: ("/" + . + "/*"),
            TargetOriginId: ("S3-" + $bucket),
            ViewerProtocolPolicy: "redirect-to-https",
            AllowedMethods: {
              Quantity: 3,
              Items: ["GET", "HEAD", "OPTIONS"],
              CachedMethods: {
                Quantity: 2,
                Items: ["GET", "HEAD"]
              }
            },
            CachePolicyId: "658327ea-f89d-4fab-a63d-7e88639e58f6",
            OriginRequestPolicyId: "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf",
            Compress: false
          }
        ]
      }'
  )
else
  ORDERED_BEHAVIORS='{"Quantity":0}'
fi

# -------------------------------------------------------------
# 4. Create or retrieve CloudFront distribution
# -------------------------------------------------------------
echo "Checking for existing CloudFront distribution for bucket: ${BUCKET}..."

# Find distribution with matching origin
EXISTING_DIST=$(aws cloudfront list-distributions \
  --profile "$PROFILE" \
  --query "DistributionList.Items[?Origins.Items[?DomainName=='${BUCKET}.s3.amazonaws.com']].Id | [0]" \
  --output text 2>/dev/null || echo "None")

if [[ "$EXISTING_DIST" != "None" && -n "$EXISTING_DIST" ]]; then
  echo "✓ Found existing distribution: ${EXISTING_DIST}"
  DIST_ID="$EXISTING_DIST"
  
  # Get existing distribution details
  DIST_JSON=$(aws cloudfront get-distribution \
    --id "$DIST_ID" \
    --profile "$PROFILE")
  
  CLOUDFRONT_DOMAIN=$(echo "$DIST_JSON" | "$JQ_CMD" -r .Distribution.DomainName)
  ETAG=$(echo "$DIST_JSON" | "$JQ_CMD" -r .ETag)
  
  echo "⚠️  Distribution already exists. To update it, you would need to modify the config."
  echo "   For now, using existing distribution as-is."
else
  echo "Creating new CloudFront distribution..."
  DIST_JSON=$(aws cloudfront create-distribution \
    --profile "$PROFILE" \
    --distribution-config "{
      \"CallerReference\": \"$(date +%s)\",
      \"Comment\": \"CDN for ${BUCKET} bucket\",
      \"Origins\": {
        \"Quantity\": 1,
        \"Items\": [{
          \"Id\": \"S3-${BUCKET}\",
          \"DomainName\": \"${BUCKET}.s3.amazonaws.com\",
          \"S3OriginConfig\": {
            \"OriginAccessIdentity\": \"\"
          },
          \"OriginAccessControlId\": \"${OAC_ID}\"
        }]
      },
      \"DefaultCacheBehavior\": ${DEFAULT_BEHAVIOR},
      \"CacheBehaviors\": ${ORDERED_BEHAVIORS},
      \"Enabled\": true
    }")

  DIST_ID=$(echo "$DIST_JSON" | "$JQ_CMD" -r .Distribution.Id)
  CLOUDFRONT_DOMAIN=$(echo "$DIST_JSON" | "$JQ_CMD" -r .Distribution.DomainName)
  echo "✓ Created distribution: ${DIST_ID}"
fi

# -------------------------------------------------------------
# 5. Apply S3 bucket policy (CloudFront-only access)
# -------------------------------------------------------------
echo "Applying bucket policy..."
aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --profile "$PROFILE" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"Service\": \"cloudfront.amazonaws.com\"
      },
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET}/*\",
      \"Condition\": {
        \"StringEquals\": {
          \"AWS:SourceArn\": \"arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${DIST_ID}\"
        }
      }
    }]
  }"

echo "✓ Bucket policy applied"

# -------------------------------------------------------------
# 6. Output
# -------------------------------------------------------------
echo
echo "✅ CloudFront setup complete!"
echo "-----------------------------------------"
echo "Distribution ID: ${DIST_ID}"
echo "CloudFront URL:"
echo "https://${CLOUDFRONT_DOMAIN}/"
echo

if [[ "$EXISTING_DIST" == "None" ]]; then
  echo "⏳ Distribution is now deploying (15-30 minutes)"
  echo "   Check status in AWS Console or run:"
  echo "   aws cloudfront get-distribution --id ${DIST_ID} --profile ${PROFILE}"
else
  echo "ℹ️  Using existing distribution (already deployed)"
fi
echo

if [[ ${#PUBLIC_PATHS[@]} -gt 0 ]]; then
  echo "🌍 Public paths (aggressive caching):"
  for PATH in "${PUBLIC_PATHS[@]}"; do
    echo "  https://${CLOUDFRONT_DOMAIN}/${PATH}/"
  done
  echo
fi

echo "-----------------------------------------"
echo "📝 Configuration:"
echo "  • Default paths: 5-min cache (presigned URLs, COG)"
echo "  • Public paths: 24-hour cache (static content)"
echo "  • Query strings: Forwarded (presigned URLs work)"
echo "  • Range requests: ✓ Enabled (COG tiles work)"
echo "  • Methods: GET, HEAD, OPTIONS (CORS enabled)"
echo "  • Compression: Disabled (preserves imagery)"
