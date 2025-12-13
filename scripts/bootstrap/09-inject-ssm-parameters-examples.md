# Inject secrets into AWS Systems Manager Parameter Store
# This script reads .env.ssm file and creates parameters in AWS SSM

# Step 1: Create .env.ssm from template
cp .env.ssm.example .env.ssm

# Step 2: Edit .env.ssm with your actual secrets
# Replace placeholder values with real credentials
vim .env.ssm

# Step 3: Run the script to inject parameters
./scripts/bootstrap/06-inject-ssm-parameters.sh

# Dry run (see what would be created without creating)
./scripts/bootstrap/06-inject-ssm-parameters.sh --dry-run

# Specify AWS region
./scripts/bootstrap/06-inject-ssm-parameters.sh --region ap-south-1

# Verify parameters were created
aws ssm get-parameters-by-path --path /zerotouch/prod --recursive

# Verify specific parameter
aws ssm get-parameter --name /zerotouch/prod/agent-executor/postgres/password --with-decryption

# Check if ESO synced the secrets to Kubernetes
kubectl get externalsecret -A
kubectl get secret agent-executor-postgres -n intelligence-deepagents
kubectl get secret agent-executor-dragonfly -n intelligence-deepagents
kubectl get secret agent-executor-llm-keys -n intelligence-deepagents
