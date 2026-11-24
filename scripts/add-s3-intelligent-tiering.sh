#!/usr/bin/env bash
set -euo pipefail
# -------------------------------------------------------------
# Apply lifecycle policy to transition ALL objects to Intelligent-Tiering
# Usage:
#   bash add-s3-intelligent-tiering.sh <bucket-name> [profile-name]
#
# This policy:
#   - Transitions ALL objects (existing + new) to Intelligent-Tiering after 0 days
#   - Intelligent-Tiering then automatically manages tier transitions:
#     * 30 days no access → Infrequent Access
#     * 90 days no access → Archive Access (opt-in below)
#     * 180 days no access → Deep Archive Access (opt-in below)
#   - Archived objects can't be read until restored (3-12h).
#     Restore with: bash unarchive-s3-path.sh <bucket> <prefix>
#
# 🔄 To undo/remove this configuration:
#
# Remove Intelligent-Tiering configuration:
# aws s3api delete-bucket-intelligent-tiering-configuration \\
# --bucket $BUCKET --id drone-imagery-intelligent-tiering --profile $PROFILE
#
# # Remove lifecycle policy:
# aws s3api delete-bucket-lifecycle --bucket $BUCKET --profile $PROFILE
#
# Note: Objects already transitioned to Intelligent-Tiering will stay in that
# storage class. To move them back to Standard, you'd need to copy them:
# aws s3 cp s3://$BUCKET/projects/ s3://$BUCKET/projects/ \\
#  --recursive --storage-class STANDARD --metadata-directive COPY
#
# -------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <bucket-name> [profile-name]"
  exit 1
fi

BUCKET="$1"
PROFILE="${2:-admin}"

echo "========================================="
echo "🪣 Bucket: $BUCKET"
echo "👔 Profile: $PROFILE"
echo "========================================="

# -------------------------------------------------------------
# Step 1: Create Intelligent-Tiering configuration with archive tiers
# -------------------------------------------------------------
echo "Step 1: Configuring Intelligent-Tiering with archive access..."
CONFIG_FILE=$(mktemp)
cat > "$CONFIG_FILE" <<'EOF'
{
  "Id": "drone-imagery-intelligent-tiering",
  "Status": "Enabled",
  "Filter": {
    "Prefix": "projects/"
  },
  "Tierings": [
    {
      "Days": 90,
      "AccessTier": "ARCHIVE_ACCESS"
    },
    {
      "Days": 180,
      "AccessTier": "DEEP_ARCHIVE_ACCESS"
    }
  ]
}
EOF

if aws s3api put-bucket-intelligent-tiering-configuration \
  --bucket "$BUCKET" \
  --id "drone-imagery-intelligent-tiering" \
  --intelligent-tiering-configuration "file://$CONFIG_FILE" \
  --profile "$PROFILE" 2>&1; then
  echo "  ✅ Archive tiers enabled (90d → Archive, 180d → Deep Archive)"
else
  echo "  ℹ️  Intelligent-Tiering configuration already exists or updated"
fi

rm "$CONFIG_FILE"
echo

# -------------------------------------------------------------
# Step 2: Create lifecycle policy to transition all objects
# -------------------------------------------------------------
echo "Step 2: Applying lifecycle policy to transition all objects..."
POLICY_FILE=$(mktemp)
cat > "$POLICY_FILE" <<'EOF'
{
  "Rules": [
    {
      "ID": "transition-to-intelligent-tiering",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "projects/"
      },
      "Transitions": [
        {
          "Days": 0,
          "StorageClass": "INTELLIGENT_TIERING"
        }
      ]
    }
  ]
}
EOF

if aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration "file://$POLICY_FILE" \
  --profile "$PROFILE" 2>&1; then
  echo "  ✅ Lifecycle policy applied (all objects → Intelligent-Tiering)"
else
  echo "  ℹ️  Lifecycle policy already exists or updated"
fi

rm "$POLICY_FILE"
echo

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
echo "========================================="
echo "✅ Configuration Complete!"
echo "========================================="
echo
echo "📊 What happens now:"
echo "  1. ALL objects under projects/* will transition to Intelligent-Tiering"
echo "  2. Objects not accessed for 30 days → Infrequent Access tier"
echo "  3. Objects not accessed for 90 days → Archive Access"
echo "  4. Objects not accessed for 180 days → Deep Archive Access"
echo "  5. Archived objects need a restore (3-12h): unarchive-s3-path.sh"
echo
echo "💰 Cost savings for 5-15MB images:"
echo "  - Standard S3: \$0.023/GB/month"
echo "  - Intelligent-Tiering Frequent: \$0.023/GB/month"
echo "  - Intelligent-Tiering Infrequent: \$0.0125/GB/month (46% savings)"
echo "  - Intelligent-Tiering Archive: \$0.0036/GB/month (84% savings)"
echo "  - Intelligent-Tiering Deep Archive: \$0.00099/GB/month (96% savings)"
echo "  - Monitoring fee: \$0.0025/1000 objects"
echo
echo "⏳ Restore delays:"
echo "  - Archive Access: 3-5 hours after a restore request"
echo "  - Deep Archive Access: up to 12 hours after a restore request"
echo
echo " Verify configuration:"
echo "  aws s3api get-bucket-intelligent-tiering-configuration \\"
echo "    --bucket $BUCKET --id drone-imagery-intelligent-tiering --profile $PROFILE"
echo
echo "  aws s3api get-bucket-lifecycle-configuration \\"
echo "    --bucket $BUCKET --profile $PROFILE"
