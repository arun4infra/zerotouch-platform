#!/bin/bash
# generators.sh - Property-based test data generators for AgentSandboxService

# Generate random valid claim specification
generate_random_claim_spec() {
  local claim_name="$1"
  
  # Random image selection
  local images=("busybox:latest" "alpine:latest" "ubuntu:20.04" "nginx:alpine")
  local image="${images[$((RANDOM % ${#images[@]}))]}"
  
  # Random size selection
  local sizes=("micro" "small" "medium" "large")
  local size="${sizes[$((RANDOM % ${#sizes[@]}))]}"
  
  # Random storage size (1-20 GB)
  local storage_gb=$((RANDOM % 20 + 1))
  
  # Random NATS configuration
  local stream="TEST_STREAM_$((RANDOM % 100))"
  local consumer="test-consumer-$((RANDOM % 100))"
  
  cat <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: $claim_name
  namespace: $NAMESPACE
spec:
  image: $image
  size: $size
  storageGB: $storage_gb
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "$stream"
    consumer: "$consumer"
EOF
}

# Generate claim with persistent storage focus
generate_persistent_claim_spec() {
  local claim_name="$1"
  
  # Use busybox for reliable file operations
  local storage_gb=$((RANDOM % 10 + 5))  # 5-15 GB
  
  cat <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: $claim_name
  namespace: $NAMESPACE
spec:
  image: busybox:latest
  command: ["sleep", "3600"]
  size: micro
  storageGB: $storage_gb
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "PERSIST_TEST_STREAM"
    consumer: "persist-test-consumer"
EOF
}

# Generate claim with NATS configuration
generate_nats_claim_spec() {
  local claim_name="$1"
  
  # Random NATS configuration
  local stream="KEDA_TEST_STREAM_$((RANDOM % 100))"
  local consumer="keda-test-consumer-$((RANDOM % 100))"
  
  cat <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: $claim_name
  namespace: $NAMESPACE
spec:
  image: busybox:latest
  size: micro
  storageGB: 5
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "$stream"
    consumer: "$consumer"
EOF
}

# Generate claim with HTTP configuration
generate_http_claim_spec() {
  local claim_name="$1"
  
  # Random HTTP configuration
  local http_port=$((RANDOM % 9000 + 8000))  # 8000-16999
  local health_paths=("/health" "/healthz" "/status" "/ping")
  local ready_paths=("/ready" "/readiness" "/ready-check")
  local session_affinities=("None" "ClientIP")
  
  local health_path="${health_paths[$((RANDOM % ${#health_paths[@]}))]}"
  local ready_path="${ready_paths[$((RANDOM % ${#ready_paths[@]}))]}"
  local session_affinity="${session_affinities[$((RANDOM % ${#session_affinities[@]}))]}"
  
  cat <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: $claim_name
  namespace: $NAMESPACE
spec:
  image: busybox:latest
  size: micro
  storageGB: 5
  httpPort: $http_port
  healthPath: "$health_path"
  readyPath: "$ready_path"
  sessionAffinity: "$session_affinity"
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "HTTP_TEST_STREAM"
    consumer: "http-test-consumer"
EOF
}

# Generate claim with secret configuration
generate_secret_claim_spec() {
  local claim_name="$1"
  local iteration="$2"
  
  # Random number of secrets (1-3)
  local num_secrets=$((RANDOM % 3 + 1))
  
  local secret_config=""
  for i in $(seq 1 $num_secrets); do
    secret_config="$secret_config
  secret${i}Name: test-secret-${iteration}-${i}"
  done
  
  cat <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: $claim_name
  namespace: $NAMESPACE
spec:
  image: busybox:latest
  size: micro
  storageGB: 5$secret_config
  nats:
    url: "nats://nats-headless.nats.svc.cluster.local:4222"
    stream: "SECRET_TEST_STREAM"
    consumer: "secret-test-consumer"
EOF
}

# Generate random file content for persistence testing
generate_random_file_content() {
  local file_size=$((RANDOM % 1000 + 100))  # 100-1099 bytes
  head -c $file_size /dev/urandom | base64 | tr -d '\n'
}

# Generate random file name
generate_random_file_name() {
  echo "test-file-$((RANDOM % 1000)).txt"
}