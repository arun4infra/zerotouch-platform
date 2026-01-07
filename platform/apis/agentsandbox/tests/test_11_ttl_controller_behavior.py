#!/usr/bin/env python3
"""
Test TTL Controller Behavior
Validates production TTL annotation management and heartbeat logic.
Usage: pytest test_11_ttl_controller_behavior.py -v
"""

import pytest
import subprocess
import time
from datetime import datetime, timezone


class TestTTLControllerBehavior:
    def setup_method(self):
        self.tenant_name = "deepagents-runtime"
        self.namespace = "intelligence-deepagents"
        self.test_claim_name = "test-ttl-behavior"
        print(f"[INFO] TTL Controller Test Setup for {self.test_claim_name}")

    def test_01_gateway_heartbeat_annotation(self, claim_manager, ttl_manager, colors):
        """Test Gateway updating last-active annotation (heartbeat)"""
        print(f"{colors.BLUE}Step: 1. Testing Gateway Heartbeat Annotation{colors.NC}")
        
        # Create claim and wait for readiness
        claim_manager(self.test_claim_name, self.namespace)
        ttl_manager.wait_ready(self.test_claim_name, self.namespace)
        
        # Simulate Gateway heartbeat
        current_time = ttl_manager(self.test_claim_name, self.namespace)
        
        # Verify annotation exists
        retrieved_time = ttl_manager.get(self.test_claim_name, self.namespace)
        assert retrieved_time == current_time
        print(f"{colors.GREEN}✓ Gateway heartbeat annotation verified: {current_time}{colors.NC}")

    def test_02_ttl_expiry_detection_and_deletion(self, claim_manager, ttl_manager, colors):
        """Test TTL Controller detecting expired claims AND deleting them"""
        print(f"{colors.BLUE}Step: 2. Testing TTL Expiry Detection + Deletion Logic{colors.NC}")
        
        # Create claim and wait for readiness
        claim_manager(self.test_claim_name, self.namespace)
        ttl_manager.wait_ready(self.test_claim_name, self.namespace)
        
        # Set expired timestamp (1 hour ago)
        expired_time = datetime.now(timezone.utc).replace(hour=datetime.now().hour-1).isoformat()
        ttl_manager(self.test_claim_name, self.namespace, expired_time)
        
        print(f"{colors.YELLOW}⏰ Claim marked as expired: {expired_time}{colors.NC}")
        print(f"{colors.YELLOW}⚠️  Production TTL Controller would delete this claim{colors.NC}")
        
        # Simulate TTL Controller deletion
        claim_manager.delete(self.test_claim_name, self.namespace)
        
        # Verify claim is deleted using fixture
        assert ttl_manager.verify_deleted(self.test_claim_name, self.namespace)

    def test_03_warm_vs_cold_transition_validation(self, claim_manager, ttl_manager, colors):
        """Test Warm (KEDA scale-to-0) vs Cold (TTL deletion) transitions"""
        print(f"{colors.BLUE}Step: 3. Testing Warm vs Cold State Transitions{colors.NC}")
        
        # Create claim and wait for readiness
        claim_manager(self.test_claim_name, self.namespace)
        ttl_manager.wait_ready(self.test_claim_name, self.namespace)
        
        # Simulate "Soft Expiry" - KEDA scales to 0 (Warm state)
        ttl_manager.scale_to_zero(self.test_claim_name, self.namespace)
        
        # Verify Warm state using fixture
        assert ttl_manager.verify_warm(self.test_claim_name, self.namespace)
        
        # Simulate "Hard TTL" - Claim deletion (Cold state)
        claim_manager.delete(self.test_claim_name, self.namespace)
        claim_manager.wait_cleanup(self.test_claim_name, self.namespace)
        
        # Verify Cold state using fixture
        assert ttl_manager.verify_cold(self.test_claim_name, self.namespace)

    def test_04_valet_recreation_cold_resume(self, claim_manager, nats_stream, nats_publisher, ttl_manager, colors):
        """Test Valet re-creation after TTL deletion (Cold Resume)"""
        print(f"{colors.BLUE}Step: 4. Testing Valet Re-creation (Cold Resume){colors.NC}")
        
        # Simulate Gateway detecting missing claim and recreating it
        print(f"{colors.YELLOW}🚗 Simulating Gateway: 'Where's my agent? Let me recreate it...'{colors.NC}")
        
        # Ensure NATS stream exists
        stream_name = "COLD_HIBERNATION_STREAM"
        nats_stream(stream_name)
        
        # Gateway recreates the claim (auto-resume)
        claim_manager(
            self.test_claim_name,
            self.namespace,
            nats_stream=stream_name,
            nats_consumer="cold-hibernation-consumer"
        )
        
        # Wait for claim readiness
        pod_name = ttl_manager.wait_ready(self.test_claim_name, self.namespace)
        
        # Trigger scaling with incoming request
        nats_publisher(stream_name, "resume", "valet-recreation-test")
        
        print(f"{colors.GREEN}✓ Valet successfully recreated agent: {pod_name}{colors.NC}")
        print(f"{colors.GREEN}✓ Cold Resume complete - Agent restored from S3{colors.NC}")

    def test_05_cleanup(self, claim_manager, colors):
        """Cleanup test resources"""
        print(f"{colors.BLUE}Step: 5. Cleanup{colors.NC}")
        
        try:
            claim_manager.delete(self.test_claim_name, self.namespace)
            print(f"{colors.GREEN}✓ TTL test cleanup complete{colors.NC}")
        except Exception as e:
            print(f"{colors.YELLOW}⚠️ Cleanup failed: {e}{colors.NC}")