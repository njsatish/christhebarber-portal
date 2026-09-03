# Private Setmore Compatibility-Test Deployment

This package deploys the already-tested `index.mjs` as a private AWS Lambda. It creates no API Gateway, Lambda Function URL, secret, customer record, or booking mutation.

## Install

```bash
cd "$HOME/Downloads"
mkdir -p "$HOME/Downloads/christhebarber-portal/infrastructure" \
         "$HOME/Downloads/christhebarber-portal/scripts"
cp chris-the-barber-setmore-compatibility-test.yaml \
  "$HOME/Downloads/christhebarber-portal/infrastructure/"
cp deploy_setmore_compatibility_test_no_git.sh \
  "$HOME/Downloads/christhebarber-portal/scripts/"
chmod +x "$HOME/Downloads/christhebarber-portal/scripts/deploy_setmore_compatibility_test_no_git.sh"
```

## Deploy and invoke

```bash
cd "$HOME/Downloads/christhebarber-portal"
./scripts/deploy_setmore_compatibility_test_no_git.sh
DEPLOY_EXIT=$?
echo "Setmore AWS compatibility-test exit code: $DEPLOY_EXIT"
```

## Created resources

- One private Node.js 22 Lambda
- One least-privilege IAM execution role
- One retained CloudWatch log group
- One private, encrypted, versioned artifact bucket if it does not already exist

## Delete the compatibility stack

The retained log group remains after stack deletion and can be removed separately after review.

```bash
aws cloudformation delete-stack \
  --profile default \
  --region us-east-1 \
  --stack-name chris-the-barber-setmore-compatibility-test
aws cloudformation wait stack-delete-complete \
  --profile default \
  --region us-east-1 \
  --stack-name chris-the-barber-setmore-compatibility-test
```
