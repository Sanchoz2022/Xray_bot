#!/usr/bin/env python3
"""
Test VLESS URL generation with synchronized Reality keys.
"""

import sys
import os
sys.path.append('/home/sanchoz2022/Project/CascadeProjects/windsurf-project')

from server_manager import ServerManager
import uuid

def test_vless_generation():
    """Test VLESS URL generation with current Reality keys."""
    print("Testing VLESS URL generation with synchronized Reality keys...")
    
    server_manager = ServerManager()
    
    # Generate a test UUID
    test_uuid = str(uuid.uuid4())
    print(f"Test UUID: {test_uuid}")
    
    try:
        # Generate VLESS URL with email and user_id
        test_email = "test@example.com"
        vless_url = server_manager.generate_vless_url(test_email, test_uuid)
        print(f"\nGenerated VLESS URL:")
        print(vless_url)
        
        # Parse and verify the URL components
        if vless_url.startswith("vless://"):
            print("\n✅ URL format is correct (starts with vless://)")
            
            # Check for key components
            if "194.87.30.246:443" in vless_url:
                print("✅ Server IP and port are correct")
            else:
                print("❌ Server IP/port missing or incorrect")
                
            if "security=reality" in vless_url:
                print("✅ Reality security is enabled")
            else:
                print("❌ Reality security not found")
                
            if "pbk=Jincq2RErmxlKaWFtLpAl6bRdtK_vPGW9J5p_uC9dQ0" in vless_url:
                print("✅ Correct public key is present")
            else:
                print("❌ Public key missing or incorrect")
                
            if "sid=f59b36643359264f" in vless_url:
                print("✅ Correct short ID is present")
            else:
                print("❌ Short ID missing or incorrect")
                
            if "sni=www.google.com" in vless_url:
                print("✅ SNI is correct")
            else:
                print("❌ SNI missing or incorrect")
                
            return True
        else:
            print("❌ Invalid VLESS URL format")
            return False
            
    except Exception as e:
        print(f"❌ Error generating VLESS URL: {e}")
        return False

if __name__ == "__main__":
    success = test_vless_generation()
    sys.exit(0 if success else 1)
