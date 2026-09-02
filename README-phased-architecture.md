# Chris the Barber phased AWS architecture

## Files

- `infrastructure/chris-the-barber-phased.yaml`: parameterized CloudFormation template.
- `scripts/deploy-phased-architecture.sh`: guarded deploy, validation, website sync, Git commit, and push script.

## Phases

- `Phase1`: private S3, CloudFront OAC, ACM certificate binding, Route 53, security headers, and CloudFront WAF.
- `Phase2`: all Phase 1 resources plus Setmore Secrets Manager placeholder, Node.js availability Lambda, HTTP API, throttling, logs, and alarm.
- `Phase3`: all prior resources plus encrypted DynamoDB temporary-state tables, SQS and DLQ, and a Cognito admin pool with MFA.

Phase 3 deliberately provisions foundations only. Customer mutation endpoints are not exposed until Setmore contracts, deposit behavior, verification policy, and notification behavior are tested.

## Install into the project

```bash
mkdir -p "$HOME/Downloads/christhebarber-portal/infrastructure" \
         "$HOME/Downloads/christhebarber-portal/scripts"
cp chris-the-barber-phased.yaml \
  "$HOME/Downloads/christhebarber-portal/infrastructure/"
cp deploy-phased-architecture.sh \
  "$HOME/Downloads/christhebarber-portal/scripts/"
chmod +x "$HOME/Downloads/christhebarber-portal/scripts/deploy-phased-architecture.sh"
```

## Phase 1 deployment

```bash
cd "$HOME/Downloads/christhebarber-portal"
export AWS_PROFILE=default
export AWS_REGION=us-east-1
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:460425809139:certificate/REPLACE_ME"
export PHASE=Phase1
./scripts/deploy-phased-architecture.sh
```

## Phase 2 deployment

Prefer updating the secret after deployment instead of placing it in shell history:

```bash
cd "$HOME/Downloads/christhebarber-portal"
export AWS_PROFILE=default
export AWS_REGION=us-east-1
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:460425809139:certificate/REPLACE_ME"
export PHASE=Phase2
./scripts/deploy-phased-architecture.sh

aws secretsmanager put-secret-value \
  --profile default \
  --region us-east-1 \
  --secret-id /prod/chris-the-barber/setmore/oauth \
  --secret-string file://setmore-secret-local.json
rm -f setmore-secret-local.json
```

`setmore-secret-local.json` must contain `{"refreshToken":"..."}` and must never be committed.

## Phase 3 deployment

```bash
cd "$HOME/Downloads/christhebarber-portal"
export AWS_PROFILE=default
export AWS_REGION=us-east-1
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:460425809139:certificate/REPLACE_ME"
export ALERT_EMAIL="REPLACE_WITH_APPROVED_ALERT_EMAIL"
export PHASE=Phase3
./scripts/deploy-phased-architecture.sh
```
