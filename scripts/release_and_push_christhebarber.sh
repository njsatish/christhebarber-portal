#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_ACCOUNT="460425809139"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_DIR="${PROJECT_DIR:-$HOME/Downloads/christhebarber-portal}"
SITE_STACK="${SITE_STACK:-chris-the-barber-phase1-core}"
API_STACK="${API_STACK:-chris-the-barber-availability-api}"
DOMAIN="christhebarber.denduluru.com"
BRANCH="${BRANCH:-chris-the-barber-v1}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-Publish availability, hours, reviews, and portfolio updates}"
GITHUB_REPO_NAME="${GITHUB_REPO_NAME:-christhebarber-portal}"

log() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
trap 'fail "Release stopped near line $LINENO. No Git commit was created after a failed deployment."' ERR

for command_name in aws curl git python3; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required."
done

[[ -d "$PROJECT_DIR" ]] || fail "Project directory not found: $PROJECT_DIR"
[[ -s "$PROJECT_DIR/index.html" ]] || fail "index.html is missing or empty."
[[ -s "$PROJECT_DIR/assets/styles.css" ]] || fail "assets/styles.css is missing or empty."
[[ -s "$PROJECT_DIR/assets/site.js" ]] || fail "assets/site.js is missing or empty."

log "Validating AWS account and deployed stacks"
ACCOUNT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
[[ "$ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "Expected AWS account $EXPECTED_ACCOUNT, found $ACCOUNT."

SITE_STATUS="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$SITE_STACK" \
  --query 'Stacks[0].StackStatus' \
  --output text)"
[[ "$SITE_STATUS" == "CREATE_COMPLETE" || "$SITE_STATUS" == "UPDATE_COMPLETE" ]] \
  || fail "Site stack status is $SITE_STATUS."

API_STATUS="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$API_STACK" \
  --query 'Stacks[0].StackStatus' \
  --output text)"
[[ "$API_STATUS" == "CREATE_COMPLETE" || "$API_STATUS" == "UPDATE_COMPLETE" ]] \
  || fail "Availability API stack status is $API_STATUS."

SITE_BUCKET="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$SITE_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='SiteBucketName'].OutputValue" \
  --output text)"
DISTRIBUTION_ID="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$SITE_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
  --output text)"
API_ENDPOINT="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$API_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='AvailabilityEndpoint'].OutputValue" \
  --output text)"

[[ -n "$SITE_BUCKET" && "$SITE_BUCKET" != "None" ]] || fail "Site bucket output is missing."
[[ -n "$DISTRIBUTION_ID" && "$DISTRIBUTION_ID" != "None" ]] || fail "CloudFront output is missing."
[[ -n "$API_ENDPOINT" && "$API_ENDPOINT" != "None" ]] || fail "Availability endpoint output is missing."

printf 'AWS account: %s\nSite bucket: %s\nCloudFront: %s\nAvailability API: %s\n' \
  "$ACCOUNT" "$SITE_BUCKET" "$DISTRIBUTION_ID" "$API_ENDPOINT"

log "Validating local public files"
cd "$PROJECT_DIR"

# Required calendar files when calendar markup is installed.
if grep -q 'data-availability-calendar' index.html; then
  [[ -s assets/availability-calendar.css ]] || fail "Calendar CSS is missing."
  [[ -s assets/availability-calendar.js ]] || fail "Calendar JavaScript is missing."
  node --check assets/availability-calendar.js >/dev/null
fi

# Required gallery files when gallery markup is installed.
if grep -q 'portfolio-gallery' index.html; then
  [[ -s assets/work-gallery.css ]] || fail "Gallery CSS is missing."
  [[ -s assets/work-gallery.js ]] || fail "Gallery JavaScript is missing."
  node --check assets/work-gallery.js >/dev/null
  for number in 01 02 03 04 05 06 07; do
    [[ -s "assets/images/chris-work-${number}.webp" ]] \
      || fail "Gallery image assets/images/chris-work-${number}.webp is missing."
  done
fi

# Reject common secret files before deployment or Git staging.
if find . -type f \
  \( -name '.env' -o -name '.env.*' -o -name '*secret*.json' -o -name '*.pem' -o -name '*.key' \) \
  ! -name '.env.example' \
  ! -path './.git/*' | grep -q .; then
  find . -type f \
    \( -name '.env' -o -name '.env.*' -o -name '*secret*.json' -o -name '*.pem' -o -name '*.key' \) \
    ! -name '.env.example' \
    ! -path './.git/*' >&2
  fail "Potential secret file found. Remove it before release."
fi

log "Testing the live availability API"
if date -v+1d +%Y-%m-%d >/dev/null 2>&1; then
  TEST_DATE="$(date -v+1d +%Y-%m-%d)"
else
  TEST_DATE="$(date -d tomorrow +%Y-%m-%d)"
fi
API_RESULT="$(mktemp)"
HTTP_CODE="$(curl --silent --show-error \
  --output "$API_RESULT" \
  --write-out '%{http_code}' \
  --request POST \
  "$API_ENDPOINT" \
  --header 'Content-Type: application/json' \
  --header "Origin: https://$DOMAIN" \
  --data "{\"startDate\":\"$TEST_DATE\",\"endDate\":\"$TEST_DATE\"}")"
[[ "$HTTP_CODE" == "200" ]] || { cat "$API_RESULT" >&2; rm -f "$API_RESULT"; fail "Availability API returned HTTP $HTTP_CODE."; }
python3 - "$API_RESULT" <<'PY'
import json, sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text())
if not isinstance(payload.get("slots"), list):
    raise SystemExit("Availability response does not contain a slots array.")
if payload.get("slotCount") != len(payload["slots"]):
    raise SystemExit("Availability slotCount does not match the slots array.")
print(f"Availability API healthy. Slot count: {payload['slotCount']}")
PY
rm -f "$API_RESULT"

log "Publishing public website files"
aws s3 sync "$PROJECT_DIR/" "s3://$SITE_BUCKET/" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --delete \
  --exclude '.git/*' \
  --exclude '.gitignore' \
  --exclude '.DS_Store' \
  --exclude 'backend/*' \
  --exclude 'infrastructure/*' \
  --exclude 'scripts/*' \
  --exclude '*.sh' \
  --exclude 'README*.md' \
  --exclude '*.backup.*' \
  --exclude 'setmore-secret-local.json' \
  --exclude '*.pem' \
  --exclude '*.key'

INVALIDATION_ID="$(aws cloudfront create-invalidation \
  --profile "$AWS_PROFILE" \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths '/*' \
  --query 'Invalidation.Id' \
  --output text)"
echo "CloudFront invalidation: $INVALIDATION_ID"
aws cloudfront wait distribution-deployed \
  --profile "$AWS_PROFILE" \
  --id "$DISTRIBUTION_ID"

log "Validating live website"
LIVE_HTML="$(mktemp)"
LIVE_CODE="000"
for attempt in 1 2 3 4 5 6 7 8; do
  LIVE_CODE="$(curl --silent --show-error --location \
    --output "$LIVE_HTML" \
    --write-out '%{http_code}' \
    --max-time 30 \
    "https://$DOMAIN/" || true)"
  if [[ "$LIVE_CODE" == "200" ]] && grep -qi 'Chris Fleming' "$LIVE_HTML"; then
    break
  fi
  echo "Attempt $attempt: HTTP $LIVE_CODE. Retrying in 15 seconds."
  sleep 15
done
[[ "$LIVE_CODE" == "200" ]] || fail "Live website returned HTTP $LIVE_CODE."
grep -qi 'Chris Fleming' "$LIVE_HTML" || fail "Live homepage does not contain expected Chris Fleming content."
if grep -q 'data-availability-calendar' index.html; then
  grep -q 'data-availability-calendar' "$LIVE_HTML" || fail "Live availability calendar markup was not found."
fi
if grep -q 'portfolio-gallery' index.html; then
  grep -q 'portfolio-gallery' "$LIVE_HTML" || fail "Live portfolio gallery markup was not found."
fi
rm -f "$LIVE_HTML"
echo "Live validation passed: https://$DOMAIN"

log "Preparing Git repository after successful deployment"
cat > .gitignore <<'EOF'
.DS_Store
.env
.env.*
!.env.example
setmore-secret-local.json
*.pem
*.key
node_modules/
.aws-sam/
samconfig.toml
coverage/
dist/
*.backup.*
EOF

if [[ ! -d .git ]]; then
  git init
fi

CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  git switch -c "$BRANCH"
elif [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git switch "$BRANCH"
  else
    git switch -c "$BRANCH"
  fi
fi

if ! git config user.name >/dev/null; then
  git config user.name "Joseph Nuthulapati"
fi
if ! git config user.email >/dev/null; then
  git config user.email "njsatish2icloud.com"
fi

git status --short --branch
git add \
  .gitignore \
  index.html \
  assets \
  book \
  robots.txt \
  sitemap.xml \
  backend \
  infrastructure \
  scripts \
  README*.md 2>/dev/null || true

git diff --cached --check
git diff --cached --stat

if git diff --cached --quiet; then
  echo "No changed files to commit."
else
  git commit -m "$COMMIT_MESSAGE"
fi

log "Configuring GitHub remote"
if ! git remote get-url origin >/dev/null 2>&1; then
  command -v gh >/dev/null 2>&1 || fail "No origin remote exists and GitHub CLI is not installed. Install/authenticate gh or add origin manually. Deployment already succeeded."
  gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated. Run 'gh auth login'. Deployment already succeeded."
  gh repo create "$GITHUB_REPO_NAME" \
    --private \
    --source=. \
    --remote=origin
fi

REMOTE_URL="$(git remote get-url origin)"
echo "Origin: $REMOTE_URL"

git push -u origin "$BRANCH"

git status --short --branch
log "Release completed"
echo "Website: https://$DOMAIN"
echo "Branch: $BRANCH"
echo "Commit: $(git rev-parse --short HEAD)"
echo "Remote: $REMOTE_URL"
