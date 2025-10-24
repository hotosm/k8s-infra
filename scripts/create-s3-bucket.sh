#!/usr/bin/env bash
set -euo pipefail
# -------------------------------------------------------------
# Create an S3 bucket and an IAM user with scoped access
# Usage:
#   ./create-s3-user.sh <bucket-name> [profile-name]
#
# Environment:
#   AWS_REGION (optional) - defaults to us-east-1
# -------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <bucket-name> [profile-name]"
  exit 1
fi

BUCKET="$1"
PROFILE="${2:-admin}"
REGION="${AWS_REGION:-us-east-1}"
IAM_USER="s3-${BUCKET}-access"

echo "========================================="
echo "🪣 Bucket: $BUCKET"
echo "👤 IAM User: $IAM_USER"
echo "🌎 Region: $REGION"
echo "👔 Profile: $PROFILE"
echo "========================================="

# -------------------------------------------------------------
# 1. Create the S3 bucket
# -------------------------------------------------------------
echo "Creating S3 bucket..."
if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$BUCKET" --profile "$PROFILE" \
    || echo "Bucket already exists, skipping."
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    --profile "$PROFILE" \
    || echo "Bucket already exists, skipping."
fi

# -------------------------------------------------------------
# 2. Create IAM user (if not exists)
# -------------------------------------------------------------
echo "Creating IAM user..."
aws iam create-user --user-name "$IAM_USER" --profile "$PROFILE" \
  2>/dev/null || echo "User already exists, skipping."

# -------------------------------------------------------------
# 3. Attach minimal S3 permissions for this bucket
# -------------------------------------------------------------
echo "Attaching inline S3 policy..."
aws iam put-user-policy \
  --user-name "$IAM_USER" \
  --policy-name "${IAM_USER}-policy" \
  --profile "$PROFILE" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"s3:ListBucket\", \"s3:GetBucketLocation\"],
        \"Resource\": \"arn:aws:s3:::$BUCKET\"
      },
      {
        \"Effect\": \"Allow\",
        \"Action\": [\"s3:PutObject\", \"s3:GetObject\", \"s3:DeleteObject\"],
        \"Resource\": \"arn:aws:s3:::$BUCKET/*\"
      }
    ]
  }"

# -------------------------------------------------------------
# 4. Create access keys
# -------------------------------------------------------------
echo "Creating access keys..."
CREDS_JSON=$(aws iam create-access-key --user-name "$IAM_USER" --profile "$PROFILE")
AWS_ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r .AccessKey.AccessKeyId)
AWS_SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r .AccessKey.SecretAccessKey)

# -------------------------------------------------------------
# 5. Output credentials
# -------------------------------------------------------------
echo
echo "✅ Done!"
echo "-----------------------------------------"
echo "Generated credentials for IAM user: $IAM_USER"
echo "-----------------------------------------"
cat <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
echo "-----------------------------------------"
echo
echo "💡 Tip: Save this as './credentials' and use it for S3 access in apps/tools."
echo
