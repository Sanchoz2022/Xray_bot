#!/usr/bin/env python3
"""
Test script to verify the get_xray_status fix is working correctly.
"""

import sys
import os
sys.path.append('/home/sanchoz2022/Project/CascadeProjects/windsurf-project')

from server_manager import ServerManager

def test_xray_status():
    """Test the get_xray_status method."""
    print("Testing Xray status check...")
    
    server_manager = ServerManager()
    status = server_manager.get_xray_status()
    
    print(f"Status result: {status}")
    
    if status.get('error'):
        print(f"❌ Error: {status['error']}")
        return False
    
    if status.get('installed'):
        print(f"✅ Xray is installed: {status.get('version', 'Unknown version')}")
    else:
        print("❌ Xray is not detected as installed")
        return False
    
    if status.get('running'):
        print("✅ Xray service is running")
        return True
    else:
        print("❌ Xray service is not running")
        return False

if __name__ == "__main__":
    success = test_xray_status()
    sys.exit(0 if success else 1)
