#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_ACCOUNT="460425809139"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-chris-the-barber-platform}"
PHASE="${PHASE:-Phase1}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/Downloads/christhebarber-portal}"
TEMPLATE="${TEMPLATE:-$PROJECT_DIR/infrastructure/chris-the-barber-phased.yaml}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-chris-the-barber-v1}"
DOMAIN="christhebarber.denduluru.com"

fail(){ echo "ERROR: $*" >&2; exit 1; }
command -v aws >/dev/null || fail "AWS CLI is required"
command -v git >/dev/null || fail "Git is required"
[[ "$AWS_REGION" == "us-east-1" ]] || fail "CloudFront WAF and ACM deployment must run in us-east-1"
[[ "$PHASE" =~ ^Phase[123]$ ]] || fail "PHASE must be Phase1, Phase2, or Phase3"
[[ -f "$TEMPLATE" ]] || fail "Template not found: $TEMPLATE"

ACCOUNT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
[[ "$ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "Wrong AWS account: $ACCOUNT"

cd "$PROJECT_DIR"
BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "$EXPECTED_BRANCH" ]] || fail "Expected branch $EXPECTED_BRANCH, found $BRANCH"

git status --short --branch
aws cloudformation validate-template --profile "$AWS_PROFILE" --region "$AWS_REGION" --template-body "file://$TEMPLATE" >/dev/null

HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-$(aws route53 list-hosted-zones-by-name --profile "$AWS_PROFILE" --dns-name denduluru.com --query "HostedZones[?Name=='denduluru.com.']|[0].Id" --output text | sed 's#^/hostedzone/##')}"
[[ -n "$HOSTED_ZONE_ID" && "$HOSTED_ZONE_ID" != "None" ]] || fail "denduluru.com hosted zone not found"
[[ -n "${CERTIFICATE_ARN:-}" ]] || fail "Export CERTIFICATE_ARN for a validated us-east-1 certificate covering $DOMAIN"

PARAMS=(
  "ProjectName=chris-the-barber"
  "Environment=prod"
  "DeploymentPhase=$PHASE"
  "DomainName=$DOMAIN"
  "HostedZoneId=$HOSTED_ZONE_ID"
  "CertificateArn=$CERTIFICATE_ARN"
)
[[ -n "${ALERT_EMAIL:-}" ]] && PARAMS+=("AlertEmail=$ALERT_EMAIL")
[[ -n "${SETMORE_REFRESH_TOKEN:-}" ]] && PARAMS+=("SetmoreRefreshToken=$SETMORE_REFRESH_TOKEN")

aws cloudformation deploy \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${PARAMS[@]}" \
  --tags Project=chris-the-barber Environment=prod ManagedBy=CloudFormation

STATUS="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)"
[[ "$STATUS" =~ ^(CREATE_COMPLETE|UPDATE_COMPLETE)$ ]] || fail "Unexpected stack status: $STATUS"

SITE_BUCKET="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='SiteBucketName'].OutputValue" --output text)"
DISTRIBUTION_ID="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" --output text)"

[[ -f index.html ]] || fail "index.html not found in $PROJECT_DIR"
aws s3 sync . "s3://$SITE_BUCKET" --profile "$AWS_PROFILE" --region "$AWS_REGION" --delete \
  --exclude '.git/*' --exclude 'infrastructure/*' --exclude 'scripts/*' --exclude '*.sh' --exclude 'README.md'
aws cloudfront create-invalidation --profile "$AWS_PROFILE" --distribution-id "$DISTRIBUTION_ID" --paths '/*' >/dev/null

for attempt in 1 2 3 4 5 6; do
  CODE="$(curl -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN/" || true)"
  [[ "$CODE" == "200" ]] && break
  sleep 20
done
[[ "$CODE" == "200" ]] || fail "HTTPS validation failed with status $CODE"

echo "Deployment succeeded. Beginning Git checks."
git status --short --branch
git add infrastructure/chris-the-barber-phased.yaml scripts/deploy-phased-architecture.sh
git diff --cached --check
git diff --cached --stat
if git diff --cached --quiet; then
  echo "No approved deployment files changed; no commit created."
else
  git commit -m "Add phased AWS booking architecture $PHASE"
  git push -u origin "$EXPECTED_BRANCH"
fi
git status --short --branch
echo "Deployment and Git workflow completed successfully."
