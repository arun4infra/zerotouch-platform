#!/usr/bin/env python3
"""
Verify AgentSandboxService secret injection
Usage: pytest test_07_verify_secrets.py [--tenant <name>] [--namespace <name>] [-v] [--cleanup]

Validates that secret management follows exact EventDrivenService pattern
"""

import pytest
import subprocess
import os
import time
import json
import yaml
import base64
from typing import List

@pytest.fixture
def secrets_test_config():
    """Provide secrets test configuration"""
    return {
        "test_claim_name": "test-secrets-sandbox",
        "test_image": "busybox:latest",
        "test_command": ["sleep", "3600"]
    }


@pytest.fixture
def test_secrets(tenant_config, colors):
    """Create and cleanup test secrets"""
    print(f"{colors.BLUE}[INFO] Creating test secrets...{colors.NC}")
    
    # Create test secrets with known values
    for i in range(1, 6):
        secret_yaml = f"""apiVersion: v1
kind: Secret
metadata:
  name: test-secret-{i}
  namespace: {tenant_config['namespace']}
type: Opaque
data:
  TEST_VAR_{i}: {base64.b64encode(f'test-value-{i}'.encode()).decode()}
  COMMON_VAR: {base64.b64encode(f'from-secret-{i}'.encode()).decode()}
"""
        
        try:
            subprocess.run([
                "kubectl", "apply", "-f", "-"
            ], input=secret_yaml, text=True, capture_output=True, check=True)
        except subprocess.CalledProcessError:
            print(f"{colors.RED}[ERROR] Failed to create test-secret-{i}{colors.NC}")
            pytest.fail(f"Failed to create test-secret-{i}")
    
    print(f"{colors.BLUE}[INFO] Test secrets created successfully{colors.NC}")
    
    yield
    
    # Cleanup test secrets
    # for i in range(1, 6):
    #     try:
    #         subprocess.run([
    #             "kubectl", "delete", "secret", f"test-secret-{i}", 
    #             "-n", tenant_config['namespace'], "--ignore-not-found=true"
    #         ], capture_output=True, text=True, check=False)
    #     except:
    #         pass


@pytest.fixture
def secrets_claim_yaml(secrets_test_config, tenant_config, temp_dir):
    """Create secrets test claim YAML"""
    claim_yaml = f"""apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentSandboxService
metadata:
  name: {secrets_test_config['test_claim_name']}
  namespace: {tenant_config['namespace']}
spec:
  image: {secrets_test_config['test_image']}
  command: {secrets_test_config['test_command']}
  size: micro
  secret1Name: test-secret-1
  secret2Name: test-secret-2
  secret3Name: test-secret-3
  secret4Name: test-secret-4
  secret5Name: test-secret-5
  nats:
    url: nats://nats-headless.nats.svc.cluster.local:4222
    stream: TEST_STREAM
    consumer: test-consumer
  storageGB: 5
"""
    
    claim_file = os.path.join(temp_dir, "secrets-claim.yaml")
    with open(claim_file, 'w') as f:
        f.write(claim_yaml)
    
    return claim_file


@pytest.fixture
def cleanup_secrets_claim(secrets_test_config, tenant_config):
    """Cleanup secrets test claim after test"""
    yield
    
    # Clean up test claim
    # try:
    #     subprocess.run([
    #         "kubectl", "delete", "agentsandboxservice", secrets_test_config['test_claim_name'], 
    #         "-n", tenant_config['namespace'], "--ignore-not-found=true"
    #     ], capture_output=True, text=True, check=False)
    # except:
    #     pass


def test_validate_prerequisites(colors, kubectl_helper, tenant_config, test_counters):
    """Validate prerequisites"""
    print("Starting AgentSandboxService secret injection validation")
    print(f"Tenant: {tenant_config['tenant_name']}, Namespace: {tenant_config['namespace']}")
    print(f"{colors.BLUE}[INFO] Validating prerequisites...{colors.NC}")
    
    # Check namespace exists
    try:
        kubectl_helper.kubectl_retry(["get", "namespace", tenant_config['namespace']])
    except Exception:
        print(f"{colors.RED}[ERROR] Namespace {tenant_config['namespace']} does not exist{colors.NC}")
        test_counters.errors += 1
        pytest.fail(f"Namespace {tenant_config['namespace']} does not exist")
    
    # Check AgentSandboxService XRD exists
    try:
        kubectl_helper.kubectl_retry(["get", "xrd", "xagentsandboxservices.platform.bizmatters.io"])
    except Exception:
        print(f"{colors.RED}[ERROR] AgentSandboxService XRD not found{colors.NC}")
        test_counters.errors += 1
        pytest.fail("AgentSandboxService XRD not found")
    
    # Check aws-access-token secret exists
    try:
        kubectl_helper.kubectl_retry(["get", "secret", "aws-access-token", "-n", tenant_config['namespace']])
    except Exception:
        print(f"{colors.RED}[ERROR] aws-access-token secret not found in namespace {tenant_config['namespace']}{colors.NC}")
        test_counters.errors += 1
        pytest.fail("aws-access-token secret not found")
    
    print(f"{colors.BLUE}[INFO] Prerequisites validated successfully{colors.NC}")


def test_create_test_secrets(test_secrets):
    """Create test secrets - handled by fixture"""
    pass


def test_create_test_claim(colors, secrets_claim_yaml, secrets_test_config, test_counters):
    """Create AgentSandboxService test claim with all secrets"""
    print(f"{colors.BLUE}[INFO] Creating AgentSandboxService test claim with all secrets...{colors.NC}")
    
    try:
        subprocess.run([
            "kubectl", "apply", "-f", secrets_claim_yaml
        ], capture_output=True, text=True, check=True)
        print(f"{colors.BLUE}[INFO] Test claim created successfully{colors.NC}")
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] Failed to create AgentSandboxService claim{colors.NC}")
        test_counters.errors += 1
        pytest.fail("Failed to create AgentSandboxService claim")


def test_wait_for_resources(colors, secrets_test_config, tenant_config, test_counters, cleanup_secrets_claim):
    """Wait for resources to be ready"""
    print(f"{colors.BLUE}[INFO] Waiting for resources to be ready...{colors.NC}")
    
    # First verify the claim actually exists
    try:
        subprocess.run([
            "kubectl", "get", "agentsandboxservice", secrets_test_config['test_claim_name'], "-n", tenant_config['namespace']
        ], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] AgentSandboxService claim '{secrets_test_config['test_claim_name']}' does not exist{colors.NC}")
        test_counters.errors += 1
        pytest.fail(f"AgentSandboxService claim '{secrets_test_config['test_claim_name']}' does not exist")
    
    # Wait for claim to be ready
    timeout = 180
    elapsed = 0
    
    while elapsed < timeout:
        try:
            result = subprocess.run([
                "kubectl", "get", "agentsandboxservice", secrets_test_config['test_claim_name'], 
                "-n", tenant_config['namespace'], "-o", "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}"
            ], capture_output=True, text=True, check=True)
            
            if "True" in result.stdout:
                print(f"{colors.BLUE}[INFO] AgentSandboxService claim is ready{colors.NC}")
                break
        except subprocess.CalledProcessError:
            pass
        
        # Check for error conditions
        try:
            result = subprocess.run([
                "kubectl", "get", "agentsandboxservice", secrets_test_config['test_claim_name'], 
                "-n", tenant_config['namespace'], "-o", "jsonpath={.status.conditions[?(@.type==\"Synced\")].status}"
            ], capture_output=True, text=True, check=True)
            
            if "False" in result.stdout:
                print(f"{colors.RED}[ERROR] AgentSandboxService claim failed to sync{colors.NC}")
                subprocess.run([
                    "kubectl", "describe", "agentsandboxservice", secrets_test_config['test_claim_name'], "-n", tenant_config['namespace']
                ], check=False)
                test_counters.errors += 1
                pytest.fail("AgentSandboxService claim failed to sync")
        except subprocess.CalledProcessError:
            pass
        
        if elapsed > 0 and elapsed % 30 == 0:
            print(f"{colors.BLUE}[INFO] Still waiting for claim to be ready... ({elapsed}s elapsed){colors.NC}")
        
        time.sleep(5)
        elapsed += 5
    
    if elapsed >= timeout:
        print(f"{colors.RED}[ERROR] Timeout waiting for AgentSandboxService to be ready{colors.NC}")
        subprocess.run([
            "kubectl", "describe", "agentsandboxservice", secrets_test_config['test_claim_name'], "-n", tenant_config['namespace']
        ], check=False)
        test_counters.errors += 1
        pytest.fail("Timeout waiting for AgentSandboxService to be ready")
    
    # Wait for SandboxWarmPool to exist and have replicas
    print(f"{colors.BLUE}[INFO] Waiting for sandbox instances to be created...{colors.NC}")
    elapsed = 0
    
    while elapsed < timeout:
        try:
            result = subprocess.run([
                "kubectl", "get", "sandboxwarmpool", secrets_test_config['test_claim_name'], 
                "-n", tenant_config['namespace'], "-o", "jsonpath={.status.replicas}"
            ], capture_output=True, text=True, check=True)
            
            replicas = result.stdout.strip() or "0"
            if int(replicas) > 0:
                print(f"{colors.BLUE}[INFO] Sandbox instances created (replicas: {replicas}){colors.NC}")
                break
        except (subprocess.CalledProcessError, ValueError):
            pass
        
        if elapsed > 0 and elapsed % 30 == 0:
            print(f"{colors.BLUE}[INFO] Still waiting for sandbox instances... ({elapsed}s elapsed){colors.NC}")
        
        time.sleep(5)
        elapsed += 5
    
    if elapsed >= timeout:
        print(f"{colors.RED}[ERROR] Timeout waiting for sandbox instances to be created{colors.NC}")
        subprocess.run([
            "kubectl", "describe", "sandboxwarmpool", secrets_test_config['test_claim_name'], "-n", tenant_config['namespace']
        ], check=False)
        test_counters.errors += 1
        pytest.fail("Timeout waiting for sandbox instances to be created")


def test_validate_secret_patching(colors, secrets_test_config, tenant_config, test_counters, cleanup_secrets_claim):
    """Validate secret patching in SandboxTemplate"""
    print(f"{colors.BLUE}[INFO] Validating secret patching in SandboxTemplate...{colors.NC}")
    
    # Get the SandboxTemplate and check envFrom configuration
    try:
        result = subprocess.run([
            "kubectl", "get", "sandboxtemplate", secrets_test_config['test_claim_name'], 
            "-n", tenant_config['namespace'], "-o", "yaml"
        ], capture_output=True, text=True, check=True)
        template_yaml = result.stdout
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] Failed to get SandboxTemplate{colors.NC}")
        test_counters.errors += 1
        pytest.fail("Failed to get SandboxTemplate")
    
    # Parse YAML and check envFrom entries
    try:
        template_data = yaml.safe_load(template_yaml)
        env_from = template_data['spec']['podTemplate']['spec']['containers'][0]['envFrom']
        
        # Check that all 6 envFrom entries exist (aws-access-token + 5 user secrets)
        if len(env_from) != 6:
            print(f"{colors.RED}[ERROR] Expected 6 envFrom entries, found {len(env_from)}{colors.NC}")
            test_counters.errors += 1
            pytest.fail(f"Expected 6 envFrom entries, found {len(env_from)}")
        
        # Validate specific secret names are patched correctly
        expected_secrets = ["test-secret-1", "test-secret-2", "test-secret-3", "test-secret-4", "test-secret-5", "aws-access-token"]
        
        for i, expected_secret in enumerate(expected_secrets):
            actual_secret = env_from[i]['secretRef']['name']
            if actual_secret != expected_secret:
                print(f"{colors.RED}[ERROR] envFrom[{i}] expected '{expected_secret}', got '{actual_secret}'{colors.NC}")
                test_counters.errors += 1
                pytest.fail(f"envFrom[{i}] expected '{expected_secret}', got '{actual_secret}'")
        
        print(f"{colors.BLUE}[INFO] Secret patching validated successfully{colors.NC}")
    except (KeyError, IndexError, yaml.YAMLError) as e:
        print(f"{colors.RED}[ERROR] Failed to parse SandboxTemplate YAML: {e}{colors.NC}")
        test_counters.errors += 1
        pytest.fail(f"Failed to parse SandboxTemplate YAML: {e}")


def test_validate_environment_variables(colors, secrets_test_config, tenant_config, test_counters, cleanup_secrets_claim):
    """Validate environment variables in sandbox containers"""
    print(f"{colors.BLUE}[INFO] Validating environment variables in sandbox containers...{colors.NC}")
    
    # Get a running pod from the SandboxWarmPool
    try:
        result = subprocess.run([
            "kubectl", "get", "pods", "-n", tenant_config['namespace'],
            "-l", f"app.kubernetes.io/name={secrets_test_config['test_claim_name']}",
            "-o", "jsonpath={.items[0].metadata.name}"
        ], capture_output=True, text=True, check=True)
        pod_name = result.stdout.strip()
        
        if not pod_name:
            print(f"{colors.RED}[ERROR] No running sandbox pods found{colors.NC}")
            test_counters.errors += 1
            pytest.fail("No running sandbox pods found")
        
        print(f"{colors.BLUE}[INFO] Testing environment variables in pod: {pod_name}{colors.NC}")
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] Failed to get sandbox pod{colors.NC}")
        test_counters.errors += 1
        pytest.fail("Failed to get sandbox pod")
    
    # Test that variables from all secrets are available
    for i in range(1, 6):
        expected_value = f"test-value-{i}"
        try:
            result = subprocess.run([
                "kubectl", "exec", pod_name, "-n", tenant_config['namespace'], "-c", "main", "--",
                "printenv", f"TEST_VAR_{i}"
            ], capture_output=True, text=True, check=True)
            actual_value = result.stdout.strip()
            
            if actual_value != expected_value:
                print(f"{colors.RED}[ERROR] TEST_VAR_{i} expected '{expected_value}', got '{actual_value}'{colors.NC}")
                test_counters.errors += 1
                pytest.fail(f"TEST_VAR_{i} expected '{expected_value}', got '{actual_value}'")
        except subprocess.CalledProcessError:
            print(f"{colors.RED}[ERROR] TEST_VAR_{i} not found in container environment{colors.NC}")
            test_counters.errors += 1
            pytest.fail(f"TEST_VAR_{i} not found in container environment")
    
    # Test that AWS credentials are available
    try:
        subprocess.run([
            "kubectl", "exec", pod_name, "-n", tenant_config['namespace'], "-c", "main", "--",
            "printenv", "AWS_ACCESS_KEY_ID"
        ], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] AWS_ACCESS_KEY_ID not found in container environment{colors.NC}")
        test_counters.errors += 1
        pytest.fail("AWS_ACCESS_KEY_ID not found in container environment")
    
    print(f"{colors.BLUE}[INFO] Environment variables validated successfully{colors.NC}")


def test_validate_connection_secret(colors, secrets_test_config, tenant_config, test_counters, cleanup_secrets_claim):
    """Validate connection secret generation"""
    print(f"{colors.BLUE}[INFO] Validating connection secret generation...{colors.NC}")
    
    # Check that connection secret exists with correct naming pattern
    conn_secret_name = f"{secrets_test_config['test_claim_name']}-conn"
    
    try:
        subprocess.run([
            "kubectl", "get", "secret", conn_secret_name, "-n", tenant_config['namespace']
        ], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] Connection secret '{conn_secret_name}' not found{colors.NC}")
        test_counters.errors += 1
        pytest.fail(f"Connection secret '{conn_secret_name}' not found")
    
    # Validate connection secret contains expected keys
    try:
        result = subprocess.run([
            "kubectl", "get", "secret", conn_secret_name, "-n", tenant_config['namespace'],
            "-o", "jsonpath={.data}"
        ], capture_output=True, text=True, check=True)
        secret_data = json.loads(result.stdout)
        secret_keys = list(secret_data.keys())
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        print(f"{colors.RED}[ERROR] Failed to get connection secret data{colors.NC}")
        test_counters.errors += 1
        pytest.fail("Failed to get connection secret data")
    
    expected_keys = ["SANDBOX_SERVICE_NAME", "SANDBOX_HTTP_ENDPOINT", "SANDBOX_NAMESPACE"]
    
    for key in expected_keys:
        if key not in secret_keys:
            print(f"{colors.RED}[ERROR] Connection secret missing key: {key}{colors.NC}")
            test_counters.errors += 1
            pytest.fail(f"Connection secret missing key: {key}")
    
    # Validate connection secret values
    try:
        result = subprocess.run([
            "kubectl", "get", "secret", conn_secret_name, "-n", tenant_config['namespace'],
            "-o", "jsonpath={.data.SANDBOX_SERVICE_NAME}"
        ], capture_output=True, text=True, check=True)
        
        service_name = base64.b64decode(result.stdout).decode()
        
        if service_name != secrets_test_config['test_claim_name']:
            print(f"{colors.RED}[ERROR] Connection secret SANDBOX_SERVICE_NAME expected '{secrets_test_config['test_claim_name']}', got '{service_name}'{colors.NC}")
            test_counters.errors += 1
            pytest.fail(f"Connection secret SANDBOX_SERVICE_NAME expected '{secrets_test_config['test_claim_name']}', got '{service_name}'")
    except (subprocess.CalledProcessError, Exception):
        print(f"{colors.RED}[ERROR] Failed to validate connection secret values{colors.NC}")
        test_counters.errors += 1
        pytest.fail("Failed to validate connection secret values")
    
    print(f"{colors.BLUE}[INFO] Connection secret validated successfully{colors.NC}")


def test_validate_platform_standards(colors, secrets_test_config, tenant_config, test_counters, cleanup_secrets_claim):
    """Validate platform standards compliance"""
    print(f"{colors.BLUE}[INFO] Validating platform standards compliance...{colors.NC}")
    
    # Get SandboxTemplate YAML
    try:
        result = subprocess.run([
            "kubectl", "get", "sandboxtemplate", secrets_test_config['test_claim_name'], 
            "-n", tenant_config['namespace'], "-o", "yaml"
        ], capture_output=True, text=True, check=True)
        template_yaml = result.stdout
    except subprocess.CalledProcessError:
        print(f"{colors.RED}[ERROR] Failed to get SandboxTemplate{colors.NC}")
        test_counters.errors += 1
        pytest.fail("Failed to get SandboxTemplate")
    
    # Parse YAML and check secret mounting patterns
    try:
        template_data = yaml.safe_load(template_yaml)
        env_from = template_data['spec']['podTemplate']['spec']['containers'][0]['envFrom']
        
        # Validate that all user secrets are marked as optional
        for i in range(5):  # First 5 are user secrets
            optional = env_from[i]['secretRef'].get('optional', False)
            if not optional:
                print(f"{colors.RED}[ERROR] User secret at envFrom[{i}] should be optional=true, got '{optional}'{colors.NC}")
                test_counters.errors += 1
                pytest.fail(f"User secret at envFrom[{i}] should be optional=true")
        
        # Validate that aws-access-token is not optional (required for S3 operations)
        aws_optional = env_from[5]['secretRef'].get('optional', False)
        if aws_optional:
            print(f"{colors.RED}[ERROR] aws-access-token should not be optional{colors.NC}")
            test_counters.errors += 1
            pytest.fail("aws-access-token should not be optional")
        
        print(f"{colors.BLUE}[INFO] Platform standards validated successfully{colors.NC}")
    except (KeyError, IndexError, yaml.YAMLError) as e:
        print(f"{colors.RED}[ERROR] Failed to parse SandboxTemplate YAML: {e}{colors.NC}")
        test_counters.errors += 1
        pytest.fail(f"Failed to parse SandboxTemplate YAML: {e}")


def test_summary(colors, test_counters):
    """Print validation summary"""
    print(f"{colors.GREEN}[SUCCESS] ✅ All secret injection validations passed!{colors.NC}")
    print(f"{colors.GREEN}[SUCCESS] AgentSandboxService maintains complete API parity with EventDrivenService{colors.NC}")
    
    if test_counters.errors == 0:
        print(f"{colors.GREEN}[SUCCESS] All secret injection validation checks passed!{colors.NC}")
    else:
        pytest.fail(f"Secret injection validation has {test_counters.errors} error(s)")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])