Here is the step-by-step flow of how **Service A** connects to its database in the **Zero-Touch** architecture.

The secret is never known by a human; it is handed directly from the Infrastructure (Crossplane) to the Application (Kubernetes Deployment).

### The 3-Step "Handshake"

#### 1. The Request (The Claim)
You commit a YAML file asking for a database. You explicitly tell Crossplane: *"When you create this, put the credentials in a secret named `agent-executor-db-conn`."*

**File:** `platform/claims/intelligence-deepagents/postgres-claim.yaml`
```yaml
apiVersion: database.zerotouch.io/v1alpha1
kind: XPostgres
metadata:
  name: agent-executor-db
  namespace: intelligence-deepagents
spec:
  parameters:
    size: medium
  # 👇 THIS IS THE BRIDGE
  writeConnectionSecretToRef:
    name: agent-executor-db-conn  # <--- You choose this name
```

#### 2. The Fulfillment (Crossplane Execution)
Crossplane provisions the CloudNativePG cluster. It automatically generates a secure, random password. It then creates a **Kubernetes Secret** in your namespace.

**Resulting Secret (Managed by K8s):**
```yaml
kind: Secret
metadata:
  name: agent-executor-db-conn
  namespace: intelligence-deepagents
data:
  username: <base64-encoded-user>
  password: <base64-encoded-random-password>
  endpoint: <base64-encoded-host> # e.g., cluster-rw.databases.svc
  port:     <base64-encoded-5432>
```

#### 3. The Connection (The Deployment)
Your Service A (`agent-executor`) Deployment doesn't contain the password. It contains a **pointer** to that secret.

**File:** `platform/claims/intelligence-deepagents/agent-executor-deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agent-executor
  namespace: intelligence-deepagents
spec:
  template:
    spec:
      containers:
        - name: app
          env:
            # 👇 READS HOST FROM THE SECRET
            - name: POSTGRES_HOST
              valueFrom:
                secretKeyRef:
                  name: agent-executor-db-conn
                  key: endpoint

            # 👇 READS PASSWORD FROM THE SECRET
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: agent-executor-db-conn
                  key: password
```

### Summary
1.  **You** define the Secret name in the Claim.
2.  **Crossplane** fills that Secret with credentials.
3.  **Deployment** reads that Secret to connect.

**Service A connects successfully without you ever knowing the password.**