#!/usr/bin/env bash
set -Eeuo pipefail
EXPECTED_ACCOUNT="460425809139"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-chris-the-barber-availability-api}"
PORTAL_DIR="${PORTAL_DIR:-$HOME/Downloads/christhebarber-portal}"
SOURCE_DIR="${SOURCE_DIR:-$PORTAL_DIR/backend/availability}"
TEMPLATE="${TEMPLATE:-$PORTAL_DIR/infrastructure/chris-the-barber-availability-api.yaml}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-chris-the-barber-artifacts-${EXPECTED_ACCOUNT}-${AWS_REGION}}"
ALLOWED_ORIGIN="https://christhebarber.denduluru.com"
TEST_START_DATE="${TEST_START_DATE:-2026-09-16}"
TEST_END_DATE="${TEST_END_DATE:-2026-09-18}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fail(){ echo "ERROR: $*" >&2; exit 1; }; log(){ printf '\n=== %s ===\n' "$*"; }
trap 'fail "Deployment stopped near line $LINENO"' ERR
for c in aws zip node python3 curl; do command -v "$c" >/dev/null || fail "$c is required"; done
[[ -f "$SOURCE_DIR/index.mjs" && -f "$SOURCE_DIR/package.json" ]] || fail "Availability source missing from $SOURCE_DIR"
[[ -f "$TEMPLATE" ]] || fail "Template missing: $TEMPLATE"
log "Validating AWS account and source"
ACCOUNT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
[[ "$ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "Wrong AWS account: $ACCOUNT"
node --check "$SOURCE_DIR/index.mjs"
PACKAGE="$WORK/availability.zip"
(cd "$SOURCE_DIR" && zip -q -j "$PACKAGE" index.mjs package.json)
SHA="$(shasum -a 256 "$PACKAGE" | awk '{print $1}')"
KEY="availability/${SHA}.zip"
log "Uploading immutable Lambda artifact"
aws s3api head-bucket --profile "$AWS_PROFILE" --bucket "$ARTIFACT_BUCKET" >/dev/null
aws s3 cp "$PACKAGE" "s3://$ARTIFACT_BUCKET/$KEY" --profile "$AWS_PROFILE" --region "$AWS_REGION" --only-show-errors
log "Validating and deploying API stack"
aws cloudformation validate-template --profile "$AWS_PROFILE" --region "$AWS_REGION" --template-body "file://$TEMPLATE" >/dev/null
aws cloudformation deploy --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --template-file "$TEMPLATE" --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset --parameter-overrides ArtifactBucket="$ARTIFACT_BUCKET" ArtifactKey="$KEY" CodeSha256="$SHA" AllowedOrigin="$ALLOWED_ORIGIN" LogRetentionDays=14 --tags Project=chris-the-barber Environment=prod ManagedBy=CloudFormation
STATUS="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)"
[[ "$STATUS" == "CREATE_COMPLETE" || "$STATUS" == "UPDATE_COMPLETE" ]] || fail "Unexpected stack status: $STATUS"
ENDPOINT="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='AvailabilityEndpoint'].OutputValue" --output text)"
FUNCTION="$(aws cloudformation describe-stacks --profile "$AWS_PROFILE" --region "$AWS_REGION" --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='FunctionName'].OutputValue" --output text)"
log "Testing valid availability request"
HTTP="$(curl -sS -o "$WORK/valid.json" -w '%{http_code}' -X POST "$ENDPOINT" -H 'Content-Type: application/json' -H "Origin: $ALLOWED_ORIGIN" --data "{\"startDate\":\"$TEST_START_DATE\",\"endDate\":\"$TEST_END_DATE\"}")"
[[ "$HTTP" == "200" ]] || { cat "$WORK/valid.json"; fail "Valid request returned HTTP $HTTP"; }
python3 - "$WORK/valid.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert isinstance(x.get('slots'),list); assert x.get('slotCount')==len(x['slots']); print(json.dumps({'slotCount':x['slotCount'],'startDate':x['startDate'],'endDate':x['endDate']},indent=2))
PY
log "Testing invalid date rejection"
BAD="$(curl -sS -o "$WORK/bad.json" -w '%{http_code}' -X POST "$ENDPOINT" -H 'Content-Type: application/json' -H "Origin: $ALLOWED_ORIGIN" --data '{"startDate":"not-a-date"}')"
[[ "$BAD" == "400" ]] || fail "Invalid request expected HTTP 400, received $BAD"
log "Testing origin rejection"
FORBIDDEN="$(curl -sS -o "$WORK/forbidden.json" -w '%{http_code}' -X POST "$ENDPOINT" -H 'Content-Type: application/json' -H 'Origin: https://example.com' --data "{\"startDate\":\"$TEST_START_DATE\"}")"
[[ "$FORBIDDEN" == "403" ]] || fail "Unapproved origin expected HTTP 403, received $FORBIDDEN"
URLS="$(aws lambda list-function-url-configs --profile "$AWS_PROFILE" --region "$AWS_REGION" --function-name "$FUNCTION" --query 'FunctionUrlConfigs | length(@)' --output text)"
[[ "$URLS" == "0" ]] || fail "Unexpected Lambda Function URL exists"
log "Availability API deployed and validated"
echo "Endpoint: $ENDPOINT"
echo "Function: $FUNCTION"
echo "Stack: $STACK_NAME ($STATUS)"
echo "Git: skipped intentionally"
