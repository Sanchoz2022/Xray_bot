#!/usr/bin/env python3
"""
Script to add test user to Xray server via gRPC API.
"""

import sys
import os
sys.path.append('/home/sanchoz2022/Project/CascadeProjects/windsurf-project')

from server_manager import ServerManager
import asyncio

async def add_test_user():
    """Add the test user to Xray server."""
    print("Adding test user to Xray server...")
    
    server_manager = ServerManager()
    
    # User details from the VLESS URL
    test_email = "user_2@xray.com"
    test_uuid = "fb03d262-7fad-413e-9fdd-b6b05d8ae5cd"
    
    try:
        # Add user to server
        success = await server_manager.add_user(test_email, test_uuid)
        
        if success:
            print(f"✅ Successfully added user {test_email} with UUID {test_uuid}")
            
            # Generate and display VLESS URL
            vless_url = server_manager.generate_vless_url(test_email, test_uuid)
            print(f"\n📋 VLESS URL:")
            print(vless_url)
            
            return True
        else:
            print(f"❌ Failed to add user {test_email}")
            return False
            
    except Exception as e:
        print(f"❌ Error adding user: {e}")
        return False

if __name__ == "__main__":
    success = asyncio.run(add_test_user())
    sys.exit(0 if success else 1)
