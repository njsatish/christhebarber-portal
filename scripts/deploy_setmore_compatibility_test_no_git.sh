#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_ACCOUNT="460425809139"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-chris-the-barber-setmore-compatibility-test}"
PROJECT_NAME="chris-the-barber"
ENVIRONMENT="test"
SOURCE_DIR="${SOURCE_DIR:-$HOME/Downloads/setmore-lambda-compatibility-test}"
PORTAL_DIR="${PORTAL_DIR:-$HOME/Downloads/christhebarber-portal}"
TEMPLATE="${TEMPLATE:-$PORTAL_DIR/infrastructure/chris-the-barber-setmore-compatibility-test.yaml}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-chris-the-barber-artifacts-${EXPECTED_ACCOUNT}-${AWS_REGION}}"
TEST_START_DATE="${TEST_START_DATE:-2026-09-09}"
TEST_END_DATE="${TEST_END_DATE:-2026-09-11}"
WORK_DIR="$(mktemp -d)"
PACKAGE_FILE="$WORK_DIR/setmore-compatibility-test.zip"
INVOKE_FILE="$WORK_DIR/invoke-result.json"
FUNCTION_ERROR_FILE="$WORK_DIR/function-error.txt"

log() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT
trap 'fail "Deployment stopped near line $LINENO."' ERR

command -v aws >/dev/null 2>&1 || fail "AWS CLI is required."
command -v zip >/dev/null 2>&1 || fail "zip is required."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."
command -v node >/dev/null 2>&1 || fail "Node.js is required for syntax validation."

[[ -f "$SOURCE_DIR/index.mjs" ]] || fail "Lambda source not found: $SOURCE_DIR/index.mjs"
[[ -f "$SOURCE_DIR/package.json" ]] || fail "package.json not found: $SOURCE_DIR/package.json"
[[ -f "$TEMPLATE" ]] || fail "CloudFormation template not found: $TEMPLATE"

log "Validating AWS identity"
ACCOUNT="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
[[ "$ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "Wrong AWS account. Expected $EXPECTED_ACCOUNT but found $ACCOUNT."
printf 'Account: %s\nProfile: %s\nRegion: %s\n' "$ACCOUNT" "$AWS_PROFILE" "$AWS_REGION"

log "Validating Lambda source"
node --check "$SOURCE_DIR/index.mjs"
python3 - "$SOURCE_DIR/package.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text())
assert data.get("type") == "module", "package.json must define type=module"
print("package.json validation passed.")
PY

log "Building deployment package"
(
  cd "$SOURCE_DIR"
  zip -q -j "$PACKAGE_FILE" index.mjs package.json
)
PACKAGE_SHA256="$(shasum -a 256 "$PACKAGE_FILE" | awk '{print $1}')"
ARTIFACT_KEY="setmore-compatibility-test/${PACKAGE_SHA256}.zip"
printf 'Package SHA-256: %s\nArtifact: s3://%s/%s\n' "$PACKAGE_SHA256" "$ARTIFACT_BUCKET" "$ARTIFACT_KEY"

log "Preparing private artifact bucket"
if ! aws s3api head-bucket --profile "$AWS_PROFILE" --bucket "$ARTIFACT_BUCKET" 2>/dev/null; then
  aws s3api create-bucket \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --bucket "$ARTIFACT_BUCKET" >/dev/null
fi
aws s3api put-public-access-block \
  --profile "$AWS_PROFILE" \
  --bucket "$ARTIFACT_BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws s3api put-bucket-encryption \
  --profile "$AWS_PROFILE" \
  --bucket "$ARTIFACT_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-versioning \
  --profile "$AWS_PROFILE" \
  --bucket "$ARTIFACT_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3 cp "$PACKAGE_FILE" "s3://$ARTIFACT_BUCKET/$ARTIFACT_KEY" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --only-show-errors

log "Validating CloudFormation template"
aws cloudformation validate-template \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --template-body "file://$TEMPLATE" >/dev/null

log "Deploying private compatibility-test stack"
aws cloudformation deploy \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    ArtifactBucket="$ARTIFACT_BUCKET" \
    ArtifactKey="$ARTIFACT_KEY" \
    CodeSha256="$PACKAGE_SHA256" \
    LogRetentionDays=14 \
  --tags \
    Project="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    ManagedBy=CloudFormation \
    Purpose=SetmoreReadOnlyCompatibilityTest

STACK_STATUS="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' \
  --output text)"
case "$STACK_STATUS" in
  CREATE_COMPLETE|UPDATE_COMPLETE) ;;
  *) fail "Unexpected stack status: $STACK_STATUS" ;;
esac

FUNCTION_NAME="$(aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='FunctionName'].OutputValue" \
  --output text)"
[[ -n "$FUNCTION_NAME" && "$FUNCTION_NAME" != "None" ]] || fail "FunctionName output was not found."
echo "Function: $FUNCTION_NAME"

log "Invoking Lambda privately from AWS"
cat > "$WORK_DIR/test-event.json" <<JSON
{
  "version": "2.0",
  "routeKey": "POST /compatibility-test",
  "rawPath": "/compatibility-test",
  "requestContext": {"requestId": "aws-private-test"},
  "body": "{\"startDate\":\"$TEST_START_DATE\",\"endDate\":\"$TEST_END_DATE\"}"
}
JSON

FUNCTION_ERROR="$(aws lambda invoke \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --cli-binary-format raw-in-base64-out \
  --payload "file://$WORK_DIR/test-event.json" \
  --query 'FunctionError' \
  --output text \
  "$INVOKE_FILE")"

if [[ "$FUNCTION_ERROR" != "None" && -n "$FUNCTION_ERROR" ]]; then
  cat "$INVOKE_FILE" >&2
  fail "Lambda reported FunctionError=$FUNCTION_ERROR"
fi

python3 - "$INVOKE_FILE" <<'PY'
import json, sys
from pathlib import Path
outer = json.loads(Path(sys.argv[1]).read_text())
status = outer.get("statusCode")
body = json.loads(outer.get("body", "{}"))
print(json.dumps(body, indent=2))
if status != 200:
    raise SystemExit(f"Expected Lambda statusCode 200, received {status}")
if body.get("compatible") is not True:
    raise SystemExit("Compatibility test did not return compatible=true")
if not isinstance(body.get("slots"), list):
    raise SystemExit("Compatibility response did not contain a slots array")
print(f"AWS compatibility validation passed with {body.get('slotCount', len(body['slots']))} slot(s).")
PY

log "Verifying function remains private"
URL_COUNT="$(aws lambda list-function-url-configs \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --query 'FunctionUrlConfigs | length(@)' \
  --output text)"
[[ "$URL_COUNT" == "0" ]] || fail "Unexpected Lambda Function URL exists."
POLICY="$(aws lambda get-policy \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --function-name "$FUNCTION_NAME" \
  --query Policy \
  --output text 2>/dev/null || true)"
[[ -z "$POLICY" || "$POLICY" == "None" ]] || warn "Lambda has a resource policy. Review it before public use."

log "Deployment and AWS compatibility test completed"
printf 'Stack: %s (%s)\nFunction: %s\nPublic endpoint: none\nReserved concurrency: unreserved account pool\nGit: skipped intentionally\n' \
  "$STACK_NAME" "$STACK_STATUS" "$FUNCTION_NAME"
