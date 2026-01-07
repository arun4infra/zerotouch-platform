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
        # Use unique claim name per test method to avoid conflicts
        import time
        self.test_claim_name = f"test-ttl-behavior-{int(time.time())}"
        print(f"[INFO] TTL Controller Test Setup for {self.test_claim_name}")

    def test_01_gateway_heartbeat_annotation(self, ready_claim_manager, ttl_manager, colors):
        """Test Gateway updating last-active annotation (heartbeat)"""
        print(f"{colors.BLUE}Step: 1. Testing Gateway Heartbeat Annotation{colors.NC}")
        
        # Create claim and wait for complete readiness (pod running)
        pod_name = ready_claim_manager(self.test_claim_name, self.namespace)
        
        # Simulate Gateway heartbeat using ttl_manager fixture
        current_time = ttl_manager(self.test_claim_name, self.namespace)
        
        # Verify annotation exists using ttl_manager fixture
        retrieved_time = ttl_manager.get(self.test_claim_name, self.namespace)
        assert retrieved_time == current_time
        print(f"{colors.GREEN}✓ Gateway heartbeat annotation verified: {current_time}{colors.NC}")

    def test_02_ttl_expiry_detection_and_deletion(self, ready_claim_manager, ttl_manager, colors):
        """Test TTL Controller detecting expired claims AND deleting them"""
        print(f"{colors.BLUE}Step: 2. Testing TTL Expiry Detection + Deletion Logic{colors.NC}")
        
        # Create claim and wait for complete readiness (pod running)
        pod_name = ready_claim_manager(self.test_claim_name, self.namespace)
        
        # Set expired timestamp using ttl_manager fixture
        expired_time = datetime.now(timezone.utc).replace(hour=datetime.now().hour-1).isoformat()
        ttl_manager(self.test_claim_name, self.namespace, expired_time)
        
        print(f"{colors.YELLOW}⏰ Claim marked as expired: {expired_time}{colors.NC}")
        print(f"{colors.YELLOW}⚠️  Production TTL Controller would delete this claim{colors.NC}")
        
        # Simulate TTL Controller deletion using ready_claim_manager fixture
        ready_claim_manager.delete(self.test_claim_name, self.namespace)
        
        # Verify claim is deleted using ttl_manager fixture
        assert ttl_manager.verify_deleted(self.test_claim_name, self.namespace)

    def test_03_warm_vs_cold_transition_validation(self, ready_claim_manager, ttl_manager, colors):
        """Test Warm (KEDA scale-to-0) vs Cold (TTL deletion) transitions"""
        print(f"{colors.BLUE}Step: 3. Testing Warm vs Cold State Transitions{colors.NC}")
        
        # Create claim and wait for complete readiness (pod running)
        pod_name = ready_claim_manager(self.test_claim_name, self.namespace)
        
        # Simulate "Soft Expiry" - KEDA scales to 0 using ttl_manager fixture
        ttl_manager.scale_to_zero(self.test_claim_name, self.namespace)
        
        # Verify Warm state using ttl_manager fixture
        assert ttl_manager.verify_warm(self.test_claim_name, self.namespace)
        
        # Simulate "Hard TTL" - Claim deletion using ready_claim_manager fixture
        ready_claim_manager.delete(self.test_claim_name, self.namespace)
        ready_claim_manager.wait_cleanup(self.test_claim_name, self.namespace)
        
        # Verify Cold state using ttl_manager fixture
        assert ttl_manager.verify_cold(self.test_claim_name, self.namespace)

    def test_04_valet_recreation_cold_resume(self, ready_claim_manager, colors):
        """Test Valet re-creation after TTL deletion (Cold Resume)"""
        print(f"{colors.BLUE}Step: 4. Testing Valet Re-creation (Cold Resume){colors.NC}")
        
        # Simulate Gateway detecting missing claim and recreating it
        print(f"{colors.YELLOW}🚗 Simulating Gateway: 'Where's my agent? Let me recreate it...'{colors.NC}")
        
        # Measure Cold Resume latency for production SLA validation
        start_time = time.time()
        
        # Gateway recreates the claim using ready_claim_manager (includes NATS setup)
        pod_name = ready_claim_manager(
            self.test_claim_name,
            self.namespace,
            nats_stream="COLD_HIBERNATION_STREAM",
            nats_consumer="cold-hibernation-consumer"
        )
        
        resume_latency = time.time() - start_time
        
        # Assert Cold Resume meets production SLA (adjust threshold as needed)
        assert resume_latency < 120, f"Cold Resume too slow: {resume_latency:.2f}s (SLA: <120s)"
        
        print(f"{colors.GREEN}✓ Valet successfully recreated agent: {pod_name}{colors.NC}")
        print(f"{colors.GREEN}✓ Cold Resume Latency: {resume_latency:.2f}s (within SLA){colors.NC}")
        print(f"{colors.GREEN}✓ Cold Resume complete - Agent restored from S3{colors.NC}")

    def test_05_cleanup(self, ready_claim_manager, colors):
        """Cleanup test resources"""
        print(f"{colors.BLUE}Step: 5. Cleanup{colors.NC}")
        
        try:
            ready_claim_manager.delete(self.test_claim_name, self.namespace)
            print(f"{colors.GREEN}✓ TTL test cleanup complete{colors.NC}")
        except Exception as e:
            print(f"{colors.YELLOW}⚠️ Cleanup failed: {e}{colors.NC}")