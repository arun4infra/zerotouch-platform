#!/usr/bin/env python3
"""
Test Deep Hibernation Composition Changes
Validates the composition updates for:
- Security context changes (runAsNonRoot: false, runAsUser: 0)
- KEDA scaling changes (minReplicaCount: 0)
- PVC deletion policy (deletionPolicy: Delete)
"""

import pytest
import subprocess
import yaml
import os


def test_composition_security_context():
    """Validate security context allows root privileges"""
    composition_path = "../compositions/agentsandbox-composition.yaml"
    
    with open(composition_path, 'r') as f:
        composition = yaml.safe_load(f)
    
    # Find SandboxTemplate resource
    sandbox_template = None
    for resource in composition['spec']['resources']:
        if resource['name'] == 'sandboxtemplate':
            sandbox_template = resource
            break
    
    assert sandbox_template is not None, "SandboxTemplate resource not found"
    
    pod_spec = sandbox_template['base']['spec']['forProvider']['manifest']['spec']['podTemplate']['spec']
    
    # Check pod-level security context
    pod_security = pod_spec['securityContext']
    assert pod_security['runAsNonRoot'] == False, "Pod securityContext runAsNonRoot should be false"
    assert pod_security['runAsUser'] == 0, "Pod securityContext runAsUser should be 0"
    assert pod_security['runAsGroup'] == 0, "Pod securityContext runAsGroup should be 0"
    assert pod_security['fsGroup'] == 0, "Pod securityContext fsGroup should be 0"
    
    # Check main container security context
    main_container = pod_spec['containers'][0]
    main_security = main_container['securityContext']
    assert main_security['runAsNonRoot'] == False, "Main container runAsNonRoot should be false"
    assert main_security['runAsUser'] == 0, "Main container runAsUser should be 0"
    assert main_security['allowPrivilegeEscalation'] == True, "Main container allowPrivilegeEscalation should be true"
    assert 'capabilities' not in main_security, "Main container should not have capabilities.drop restrictions"
    
    # Check initContainer security context
    init_container = pod_spec['initContainers'][0]
    init_security = init_container['securityContext']
    assert init_security['runAsNonRoot'] == False, "Init container runAsNonRoot should be false"
    assert init_security['runAsUser'] == 0, "Init container runAsUser should be 0"
    assert init_security['allowPrivilegeEscalation'] == True, "Init container allowPrivilegeEscalation should be true"
    assert 'capabilities' not in init_security, "Init container should not have capabilities.drop restrictions"
    
    # Check sidecar container security context
    sidecar_container = pod_spec['containers'][1]
    sidecar_security = sidecar_container['securityContext']
    assert sidecar_security['runAsNonRoot'] == False, "Sidecar container runAsNonRoot should be false"
    assert sidecar_security['runAsUser'] == 0, "Sidecar container runAsUser should be 0"
    assert sidecar_security['allowPrivilegeEscalation'] == True, "Sidecar container allowPrivilegeEscalation should be true"
    assert 'capabilities' not in sidecar_security, "Sidecar container should not have capabilities.drop restrictions"


def test_keda_scale_to_zero():
    """Validate KEDA ScaledObject allows scale-to-zero"""
    composition_path = "../compositions/agentsandbox-composition.yaml"
    
    with open(composition_path, 'r') as f:
        composition = yaml.safe_load(f)
    
    # Find ScaledObject resource
    scaled_object = None
    for resource in composition['spec']['resources']:
        if resource['name'] == 'scaledobject':
            scaled_object = resource
            break
    
    assert scaled_object is not None, "ScaledObject resource not found"
    
    scaled_spec = scaled_object['base']['spec']['forProvider']['manifest']['spec']
    assert scaled_spec['minReplicaCount'] == 0, "minReplicaCount should be 0 for scale-to-zero"
    assert scaled_spec['maxReplicaCount'] == 1, "maxReplicaCount should be 1 for single-agent model"


def test_pvc_deletion_policy():
    """Validate PVC has deletionPolicy: Delete for Cold state cleanup"""
    composition_path = "../compositions/agentsandbox-composition.yaml"
    
    with open(composition_path, 'r') as f:
        composition = yaml.safe_load(f)
    
    # Find PVC resource
    pvc_resource = None
    for resource in composition['spec']['resources']:
        if resource['name'] == 'workspace-pvc':
            pvc_resource = resource
            break
    
    assert pvc_resource is not None, "PVC resource not found"
    
    pvc_spec = pvc_resource['base']['spec']
    assert pvc_spec['deletionPolicy'] == 'Delete', "PVC deletionPolicy should be Delete for Cold state cleanup"


def test_composition_syntax_valid():
    """Validate composition YAML syntax is valid"""
    composition_path = "../compositions/agentsandbox-composition.yaml"
    
    # Test YAML parsing
    with open(composition_path, 'r') as f:
        composition = yaml.safe_load(f)
    
    assert composition is not None, "Composition should parse as valid YAML"
    assert 'apiVersion' in composition, "Composition should have apiVersion"
    assert 'kind' in composition, "Composition should have kind"
    assert composition['kind'] == 'Composition', "Should be a Composition resource"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])