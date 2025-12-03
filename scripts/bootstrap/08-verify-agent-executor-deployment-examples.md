# Verify Agent Executor Deployment
# This script performs comprehensive verification of agent-executor deployment

# Basic usage - run all checks
./scripts/bootstrap/08-verify-agent-executor-deployment.sh

# The script checks:
# - Task 4.6: ApplicationSet and Application status
# - Task 4.7: Namespace creation and labels
# - Task 4.8: ExternalSecrets and Crossplane secrets
# - Task 4.9: NATS stream and consumer
# - Task 4.10: Deployment status
# - Task 4.11: Service configuration
# - Task 4.12: KEDA ScaledObject
# - Task 4.13: Pod health and logs

# Manual verification commands (if script fails)

# Check ApplicationSet
kubectl get applicationset tenant-applications -n argocd
kubectl get application bizmatters-workloads -n argocd

# Check Application sync status
kubectl get application bizmatters-workloads -n argocd -o jsonpath='{.status.sync.status}'

# Check Application health
kubectl get application bizmatters-workloads -n argocd -o jsonpath='{.status.health.status}'

# Check namespace
kubectl get namespace intelligence-deepagents
kubectl get namespace intelligence-deepagents -o yaml | grep -A 5 labels

# Check ExternalSecrets
kubectl get externalsecret -n intelligence-deepagents
kubectl get externalsecret agent-executor-llm-keys -n intelligence-deepagents -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# Check Crossplane claims
kubectl get postgresinstance,dragonflyinstance -n intelligence-deepagents

# Check Crossplane-generated secrets
kubectl get secret agent-executor-postgres -n intelligence-deepagents
kubectl get secret agent-executor-dragonfly -n intelligence-deepagents

# Verify secret keys
kubectl get secret agent-executor-postgres -n intelligence-deepagents -o jsonpath='{.data}' | jq 'keys'

# Check NATS stream Job
kubectl get job create-agent-execution-stream -n intelligence-deepagents
kubectl logs -n intelligence-deepagents job/create-agent-execution-stream

# Check Deployment
kubectl get deployment agent-executor -n intelligence-deepagents
kubectl describe deployment agent-executor -n intelligence-deepagents

# Check Service
kubectl get service agent-executor -n intelligence-deepagents

# Check KEDA ScaledObject
kubectl get scaledobject agent-executor-scaler -n intelligence-deepagents

# Check pods
kubectl get pods -n intelligence-deepagents
kubectl describe pod -n intelligence-deepagents -l app=agent-executor

# Check pod logs
POD_NAME=$(kubectl get pods -n intelligence-deepagents -l app=agent-executor -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n intelligence-deepagents $POD_NAME -c agent-executor --tail=50

# Check init container logs (migrations)
kubectl logs -n intelligence-deepagents $POD_NAME -c run-migrations

# Check all events in namespace
kubectl get events -n intelligence-deepagents --sort-by='.lastTimestamp'

# Troubleshooting: Check ArgoCD Application details
kubectl describe application bizmatters-workloads -n argocd

# Troubleshooting: Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Troubleshooting: Check Crossplane logs
kubectl logs -n crossplane-system -l app=crossplane --tail=100

# Troubleshooting: Check ESO logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=100
