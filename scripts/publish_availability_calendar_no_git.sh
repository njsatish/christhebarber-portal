#!/usr/bin/env bash
set -Eeuo pipefail
EXPECTED_ACCOUNT="460425809139"; PROFILE="${AWS_PROFILE:-default}"; REGION="us-east-1"; STACK="chris-the-barber-phase1-core"; SITE="$HOME/Downloads/christhebarber-portal"; DOMAIN="christhebarber.denduluru.com"
fail(){ echo "ERROR: $*" >&2; exit 1; }; trap 'fail "Publish stopped near line $LINENO"' ERR
[[ "$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)" == "$EXPECTED_ACCOUNT" ]] || fail "Wrong AWS account"
for f in index.html assets/availability-calendar.css assets/availability-calendar.js; do [[ -s "$SITE/$f" ]] || fail "Missing $f"; done
grep -q 'data-availability-calendar' "$SITE/index.html" || fail "Calendar markup missing"
ENDPOINT="https://pjw8t599rb.execute-api.us-east-1.amazonaws.com/api/v1/availability"
if date -v+1d +%Y-%m-%d >/dev/null 2>&1; then
  TEST_DATE="$(date -v+1d +%Y-%m-%d)"
else
  TEST_DATE="$(date -d tomorrow +%Y-%m-%d)"
fi

echo "Availability API preflight date: $TEST_DATE"

CODE="$(curl -sS -o /tmp/chris-api-check.json -w '%{http_code}' \
  --request POST \
  "$ENDPOINT" \
  --header 'Content-Type: application/json' \
  --header "Origin: https://$DOMAIN" \
  --data "{\"startDate\":\"$TEST_DATE\",\"endDate\":\"$TEST_DATE\"}")"
[[ "$CODE" == "200" ]] || fail "Availability API preflight returned $CODE"
BUCKET="$(aws cloudformation describe-stacks --profile "$PROFILE" --region "$REGION" --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='SiteBucketName'].OutputValue" --output text)"
DIST="$(aws cloudformation describe-stacks --profile "$PROFILE" --region "$REGION" --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" --output text)"
aws s3 sync "$SITE/" "s3://$BUCKET/" --profile "$PROFILE" --region "$REGION" --delete --exclude '.git/*' --exclude '.gitignore' --exclude '.DS_Store' --exclude 'infrastructure/*' --exclude 'scripts/*' --exclude 'backend/*' --exclude '*.sh' --exclude 'README*.md' --exclude '*.backup.*'
aws cloudfront create-invalidation --profile "$PROFILE" --distribution-id "$DIST" --paths '/*' >/dev/null
aws cloudfront wait distribution-deployed --profile "$PROFILE" --id "$DIST"
for i in 1 2 3 4 5 6; do HTML="$(curl -sS -L "https://$DOMAIN/")"; echo "$HTML" | grep -q 'data-availability-calendar' && break; sleep 15; done
echo "$HTML" | grep -q 'data-availability-calendar' || fail "Live calendar validation failed"
rm -f /tmp/chris-api-check.json
echo "Published: https://$DOMAIN"; echo "Git: skipped intentionally"
