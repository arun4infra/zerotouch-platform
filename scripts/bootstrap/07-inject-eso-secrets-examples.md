# Inject AWS credentials for External Secrets Operator
# This allows ESO to sync secrets from AWS SSM Parameter Store

# Basic usage
./scripts/bootstrap/03-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>

# Example
./scripts/bootstrap/03-inject-secrets.sh AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Verify ESO is working
kubectl get clustersecretstore aws-parameter-store
kubectl get externalsecret -A

# Check if secrets are synced
kubectl get secret kagent-openai -n kagent
kubectl get secret kagent-openai -n intelligence
