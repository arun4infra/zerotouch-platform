#!/usr/bin/env python3
"""
Validation script for Checkpoint 3: WebService XRD Updated

Verifies:
- XRD schema includes hostname auto-generation logic
- Composition creates HTTPRoute resources referencing public-gateway
- HTTPRoute includes correct backend service references
- Hostname generation follows <claim-name>.<namespace>.nutgraf.in pattern
"""

import subprocess
import json
import sys
import yaml
import tempfile
import os

def run_kubectl(cmd):
    """Run kubectl command and return output"""
    try:
        result = subprocess.run(f"kubectl {cmd}", shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error running kubectl {cmd}: {result.stderr}")
            return None
        return result.stdout.strip()
    except Exception as e:
        print(f"Exception running kubectl {cmd}: {e}")
        return None

def check_xrd_schema():
    """Check XRD schema supports hostname field"""
    print("Checking WebService XRD schema...")
    
    output = run_kubectl("get xrd xwebservices.platform.bizmatters.io -o json")
    if not output:
        print("❌ WebService XRD not found")
        return False
    
    try:
        xrd_data = json.loads(output)
        schema = xrd_data.get("spec", {}).get("versions", [{}])[0].get("schema", {}).get("openAPIV3Schema", {})
        hostname_prop = schema.get("properties", {}).get("spec", {}).get("properties", {}).get("hostname", {})
        
        if not hostname_prop:
            print("❌ hostname property not found in XRD schema")
            return False
        
        # Check hostname is optional (not in required fields)
        required_fields = schema.get("properties", {}).get("spec", {}).get("required", [])
        if "hostname" in required_fields:
            print("❌ hostname should be optional, but found in required fields")
            return False
        
        print("✅ XRD schema includes optional hostname field")
        return True
        
    except (json.JSONDecodeError, KeyError) as e:
        print(f"❌ Failed to parse XRD schema: {e}")
        return False

def check_composition_httproute():
    """Check composition creates HTTPRoute with proper configuration"""
    print("\nChecking WebService Composition HTTPRoute configuration...")
    
    output = run_kubectl("get composition webservice -o json")
    if not output:
        print("❌ WebService Composition not found")
        return False
    
    try:
        comp_data = json.loads(output)
        resources = comp_data.get("spec", {}).get("resources", [])
        
        # Find HTTPRoute resource
        httproute_resource = None
        for resource in resources:
            if resource.get("name") == "httproute":
                httproute_resource = resource
                break
        
        if not httproute_resource:
            print("❌ HTTPRoute resource not found in composition")
            return False
        
        # Check parentRefs reference public-gateway
        parent_refs = httproute_resource.get("base", {}).get("spec", {}).get("forProvider", {}).get("manifest", {}).get("spec", {}).get("parentRefs", [])
        if not parent_refs:
            print("❌ No parentRefs found in HTTPRoute")
            return False
        
        public_gateway_ref = next((ref for ref in parent_refs if ref.get("name") == "public-gateway" and ref.get("namespace") == "kube-system"), None)
        if not public_gateway_ref:
            print("❌ HTTPRoute does not reference public-gateway in kube-system")
            return False
        
        print("✅ HTTPRoute references public-gateway correctly")
        
        # Check patches for hostname logic
        patches = httproute_resource.get("patches", [])
        hostname_patches = [p for p in patches if "hostnames[0]" in p.get("toFieldPath", "")]
        
        if len(hostname_patches) < 2:
            print("❌ Expected 2 hostname patches (manual + auto-generated)")
            return False
        
        # Check manual hostname patch
        manual_patch = next((p for p in hostname_patches if p.get("fromFieldPath") == "spec.hostname"), None)
        if not manual_patch or manual_patch.get("policy", {}).get("fromFieldPath") != "Optional":
            print("❌ Manual hostname patch not configured correctly")
            return False
        
        # Check auto-generated hostname patch
        auto_patch = next((p for p in hostname_patches if p.get("type") == "CombineFromComposite"), None)
        if not auto_patch:
            print("❌ Auto-generated hostname patch not found")
            return False
        
        # Check format string
        fmt_string = auto_patch.get("combine", {}).get("string", {}).get("fmt", "")
        if fmt_string != "%s.%s.nutgraf.in":
            print(f"❌ Auto-generated hostname format incorrect: {fmt_string}")
            return False
        
        print("✅ Hostname generation logic configured correctly")
        
        # Check backend references
        backend_patches = [p for p in patches if "backendRefs[0]" in p.get("toFieldPath", "")]
        required_backend_patches = ["name", "port", "namespace"]
        
        for field in required_backend_patches:
            field_patch = next((p for p in backend_patches if f"backendRefs[0].{field}" in p.get("toFieldPath", "")), None)
            if not field_patch:
                print(f"❌ Backend {field} patch not found")
                return False
        
        print("✅ Backend service references configured correctly")
        return True
        
    except (json.JSONDecodeError, KeyError) as e:
        print(f"❌ Failed to parse Composition: {e}")
        return False

def test_hostname_generation():
    """Test hostname generation with a sample WebService claim"""
    print("\nTesting hostname generation logic...")
    
    # Create a test WebService claim without hostname
    test_claim = {
        "apiVersion": "platform.bizmatters.io/v1alpha1",
        "kind": "WebService",
        "metadata": {
            "name": "test-hostname-gen",
            "namespace": "default"
        },
        "spec": {
            "image": "nginx:alpine",
            "port": 80,
            "size": "micro"
        }
    }
    
    # Write to temporary file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        yaml.dump(test_claim, f)
        temp_file = f.name
    
    try:
        # Apply the test claim
        result = subprocess.run(f"kubectl apply -f {temp_file}", shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"❌ Failed to apply test claim: {result.stderr}")
            return False
        
        print("✅ Test WebService claim applied")
        
        # Wait a moment for processing
        import time
        time.sleep(5)
        
        # Check if HTTPRoute was created
        output = run_kubectl("get httproute test-hostname-gen -n default -o json")
        if not output:
            print("❌ HTTPRoute not created for test claim")
            return False
        
        try:
            httproute_data = json.loads(output)
            hostnames = httproute_data.get("spec", {}).get("hostnames", [])
            
            if not hostnames:
                print("❌ No hostnames found in created HTTPRoute")
                return False
            
            expected_hostname = "test-hostname-gen.default.nutgraf.in"
            if hostnames[0] != expected_hostname:
                print(f"❌ Incorrect hostname generated: {hostnames[0]} (expected: {expected_hostname})")
                return False
            
            print(f"✅ Correct hostname generated: {hostnames[0]}")
            
            # Check backend references
            backend_refs = httproute_data.get("spec", {}).get("rules", [{}])[0].get("backendRefs", [])
            if not backend_refs:
                print("❌ No backend references found")
                return False
            
            backend = backend_refs[0]
            if (backend.get("name") != "test-hostname-gen" or 
                backend.get("port") != 80 or 
                backend.get("namespace") != "default"):
                print(f"❌ Incorrect backend reference: {backend}")
                return False
            
            print("✅ Backend references correct")
            return True
            
        except (json.JSONDecodeError, KeyError) as e:
            print(f"❌ Failed to parse HTTPRoute: {e}")
            return False
    
    finally:
        # Cleanup
        subprocess.run(f"kubectl delete -f {temp_file} --ignore-not-found=true", shell=True, capture_output=True)
        os.unlink(temp_file)

def main():
    """Main validation function"""
    print("=== Checkpoint 3: WebService XRD Updated Validation ===\n")
    
    success = True
    
    # Check XRD schema
    if not check_xrd_schema():
        success = False
    
    # Check composition configuration
    if not check_composition_httproute():
        success = False
    
    # Test hostname generation
    if not test_hostname_generation():
        success = False
    
    print("\n" + "="*60)
    if success:
        print("✅ CHECKPOINT 3 PASSED: WebService XRD updated and working correctly")
        sys.exit(0)
    else:
        print("❌ CHECKPOINT 3 FAILED: WebService XRD validation failed")
        sys.exit(1)

if __name__ == "__main__":
    main()