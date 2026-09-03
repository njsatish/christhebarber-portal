#!/usr/bin/env bash
set -Eeuo pipefail

WEB_PROFILE="${WEB_PROFILE:-default}"
DNS_PROFILE="${DNS_PROFILE:-denduluru}"
WEB_ACCOUNT_EXPECTED="460425809139"
DNS_ACCOUNT_EXPECTED="989174615155"
AWS_REGION="us-east-1"
HOSTED_ZONE_ID="Z21S238SFANDPM"
DOMAIN="christhebarber.denduluru.com"
STACK_NAME="chris-the-barber-phase1-core"
PROJECT_DIR="${PROJECT_DIR:-$HOME/Downloads/christhebarber-portal}"
TEMPLATE="${TEMPLATE:-$PROJECT_DIR/infrastructure/chris-the-barber-phase1-core.yaml}"
CERTIFICATE_ARN="${CERTIFICATE_ARN:-arn:aws:acm:us-east-1:460425809139:certificate/7b062847-36e6-4d50-aee9-b51a9a47c802}"

log(){ printf '\n=== %s ===\n' "$*"; }
fail(){ printf '\nERROR: %s\n' "$*" >&2; exit 1; }
trap 'fail "Deployment stopped near line $LINENO"' ERR

command -v aws >/dev/null 2>&1 || fail "AWS CLI is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
[[ -f "$TEMPLATE" ]] || fail "Template not found: $TEMPLATE"
[[ -f "$PROJECT_DIR/index.html" ]] || fail "index.html not found in $PROJECT_DIR"

log "Validating AWS accounts"
WEB_ACCOUNT="$(aws sts get-caller-identity --profile "$WEB_PROFILE" --query Account --output text)"
DNS_ACCOUNT="$(aws sts get-caller-identity --profile "$DNS_PROFILE" --query Account --output text)"
[[ "$WEB_ACCOUNT" == "$WEB_ACCOUNT_EXPECTED" ]] || fail "Wrong web account: $WEB_ACCOUNT"
[[ "$DNS_ACCOUNT" == "$DNS_ACCOUNT_EXPECTED" ]] || fail "Wrong DNS account: $DNS_ACCOUNT"
echo "Web account: $WEB_ACCOUNT"
echo "DNS account: $DNS_ACCOUNT"

log "Validating DNS zone"
ZONE_NAME="$(aws route53 get-hosted-zone --profile "$DNS_PROFILE" --id "$HOSTED_ZONE_ID" --query HostedZone.Name --output text)"
[[ "$ZONE_NAME" == "denduluru.com." ]] || fail "Unexpected zone: $ZONE_NAME"
echo "Zone: $ZONE_NAME ($HOSTED_ZONE_ID)"

log "Validating ACM certificate"
CERT_STATUS="$(aws acm describe-certificate --profile "$WEB_PROFILE" --region "$AWS_REGION" --certificate-arn "$CERTIFICATE_ARN" --query Certificate.Status --output text)"
[[ "$CERT_STATUS" == "ISSUED" ]] || fail "Certificate status is $CERT_STATUS"
CERT_COVERS_DOMAIN="$(aws acm describe-certificate --profile "$WEB_PROFILE" --region "$AWS_REGION" --certificate-arn "$CERTIFICATE_ARN" --query "contains(Certificate.SubjectAlternativeNames, '$DOMAIN')" --output text)"
[[ "$CERT_COVERS_DOMAIN" == "True" || "$CERT_COVERS_DOMAIN" == "true" ]] || fail "Certificate does not cover $DOMAIN"
echo "Certificate: $CERTIFICATE_ARN"

log "Validating template"
aws cloudformation validate-template --profile "$WEB_PROFILE" --region "$AWS_REGION" --template-body "file://$TEMPLATE" >/dev/null

log "Deploying core stack"
aws cloudformation deploy \
  --profile "$WEB_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    DomainName="$DOMAIN" \
    CertificateArn="$CERTIFICATE_ARN" \
    ProjectName=chris-the-barber \
    Environment=prod \
  --tags Project=chris-the-barber Environment=prod ManagedBy=CloudFormation

STATUS="$(aws cloudformation describe-stacks --profile "$WEB_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)"
[[ "$STATUS" == "CREATE_COMPLETE" || "$STATUS" == "UPDATE_COMPLETE" ]] || fail "Unexpected stack status: $STATUS"
BUCKET="$(aws cloudformation describe-stacks --profile "$WEB_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='SiteBucketName'].OutputValue" --output text)"
DIST_ID="$(aws cloudformation describe-stacks --profile "$WEB_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" --output text)"
DIST_DOMAIN="$(aws cloudformation describe-stacks --profile "$WEB_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDomainName'].OutputValue" --output text)"

log "Uploading website"
aws s3 sync "$PROJECT_DIR/" "s3://$BUCKET/" \
  --profile "$WEB_PROFILE" \
  --region "$AWS_REGION" \
  --delete \
  --exclude '.git/*' \
  --exclude '.DS_Store' \
  --exclude 'infrastructure/*' \
  --exclude 'scripts/*' \
  --exclude '*.sh' \
  --exclude 'README*.md' \
  --exclude 'setmore-secret-local.json'

log "Creating DNS aliases in DNS account"
CHANGE_FILE="$(mktemp)"
trap 'rm -f "$CHANGE_FILE"' EXIT
cat > "$CHANGE_FILE" <<JSON
{
  "Comment": "Chris the Barber CloudFront aliases",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "$DIST_DOMAIN",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN",
        "Type": "AAAA",
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "$DIST_DOMAIN",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
JSON
CHANGE_ID="$(aws route53 change-resource-record-sets --profile "$DNS_PROFILE" --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "file://$CHANGE_FILE" --query ChangeInfo.Id --output text)"
aws route53 wait resource-record-sets-changed --profile "$DNS_PROFILE" --id "$CHANGE_ID"

log "Invalidating CloudFront"
aws cloudfront create-invalidation --profile "$WEB_PROFILE" --distribution-id "$DIST_ID" --paths '/*' >/dev/null
aws cloudfront wait distribution-deployed --profile "$WEB_PROFILE" --id "$DIST_ID"

log "Validating website"
HTTP_CODE=000
for ATTEMPT in 1 2 3 4 5 6 7 8 9 10; do
  HTTP_CODE="$(curl -sS -L -o /tmp/christhebarber-home.html -w '%{http_code}' --max-time 30 "https://$DOMAIN/" || true)"
  if [[ "$HTTP_CODE" == "200" ]] && grep -qi 'Chris Fleming' /tmp/christhebarber-home.html; then
    break
  fi
  echo "Attempt $ATTEMPT: HTTP $HTTP_CODE. Retrying in 20 seconds."
  sleep 20
done
[[ "$HTTP_CODE" == "200" ]] || fail "HTTPS validation returned $HTTP_CODE"
grep -qi 'Chris Fleming' /tmp/christhebarber-home.html || fail "Expected homepage content was not found"
rm -f /tmp/christhebarber-home.html

log "Deployment complete"
echo "Website: https://$DOMAIN"
echo "CloudFront: $DIST_DOMAIN"
echo "Stack: $STACK_NAME ($STATUS)"
echo "Git: skipped intentionally"
