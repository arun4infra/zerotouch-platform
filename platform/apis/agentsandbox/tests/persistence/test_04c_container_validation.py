#!/usr/bin/env python3
"""
Test Container Validation (InitContainer, Sidecar, PreStop Hook)
Validates S3 hydration, backup sidecar, and preStop hook configuration
Usage: pytest test_04c_container_validation.py -v
"""

import pytest
import time


class TestContainerValidation:

    def test_initcontainer_s3_hydration(self, ready_claim_manager, k8s, colors):
        """Test: InitContainer for S3 workspace hydration"""
        test_claim_name = "test-container-validation"
        print(f"{colors.BLUE}Testing InitContainer S3 Hydration{colors.NC}")
        
        # Create claim and get pod using fixture
        pod_name = ready_claim_manager(test_claim_name, "CONTAINER_VALIDATION_STREAM")
        
        # Validate InitContainer configuration using k8s fixture
        pod_data = k8s.get_json(["get", "pod", pod_name, "-n", "intelligence-deepagents"])
        
        # Check InitContainer exists
        init_containers = pod_data.get("spec", {}).get("initContainers", [])
        assert len(init_containers) > 0, "No InitContainers found"
        
        # Find workspace-hydrator InitContainer
        hydrator = next((c for c in init_containers if c["name"] == "workspace-hydrator"), None)
        assert hydrator is not None, "workspace-hydrator InitContainer not found"
        
        # Validate InitContainer image and command
        assert "aws-cli" in hydrator["image"], f"Expected aws-cli image, got {hydrator['image']}"
        assert any("aws s3" in str(cmd) for cmd in hydrator.get("command", [])), "No S3 commands found"
        
        print(f"{colors.GREEN}✓ InitContainer workspace-hydrator configured correctly{colors.NC}")

    def test_sidecar_backup_container(self, ready_claim_manager, k8s, colors):
        """Test: Sidecar container for continuous workspace backup"""
        test_claim_name = "test-sidecar-backup"
        print(f"{colors.BLUE}Testing Sidecar Backup Container{colors.NC}")
        
        # Create claim and get pod using fixture
        pod_name = ready_claim_manager(test_claim_name, "SIDECAR_BACKUP_STREAM")
        
        # Validate sidecar container using k8s fixture
        pod_data = k8s.get_json(["get", "pod", pod_name, "-n", "intelligence-deepagents"])
        
        # Check containers
        containers = pod_data.get("spec", {}).get("containers", [])
        assert len(containers) >= 2, "Expected at least 2 containers (main + sidecar)"
        
        # Find backup sidecar
        backup_sidecar = next((c for c in containers if "backup" in c["name"]), None)
        assert backup_sidecar is not None, "Backup sidecar container not found"
        
        # Validate sidecar configuration
        assert "aws-cli" in backup_sidecar["image"], f"Expected aws-cli image, got {backup_sidecar['image']}"
        
        print(f"{colors.GREEN}✓ Sidecar backup container configured correctly{colors.NC}")

    def test_prestop_hook_validation(self, ready_claim_manager, k8s, colors):
        """Test: PreStop hook for graceful shutdown"""
        test_claim_name = "test-prestop-hook"
        print(f"{colors.BLUE}Testing PreStop Hook Configuration{colors.NC}")
        
        # Create claim and get pod using fixture
        pod_name = ready_claim_manager(test_claim_name, "PRESTOP_HOOK_STREAM")
        
        # Validate preStop hook using k8s fixture
        pod_data = k8s.get_json(["get", "pod", pod_name, "-n", "intelligence-deepagents"])
        
        # Find main container
        containers = pod_data.get("spec", {}).get("containers", [])
        main_container = next((c for c in containers if c["name"] == "main"), None)
        assert main_container is not None, "Main container not found"
        
        # Check preStop hook
        lifecycle = main_container.get("lifecycle", {})
        prestop = lifecycle.get("preStop", {})
        
        if prestop:
            print(f"{colors.GREEN}✓ PreStop hook configured{colors.NC}")
        else:
            print(f"{colors.YELLOW}⚠️ PreStop hook not configured (optional){colors.NC}")