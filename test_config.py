#!/usr/bin/env python3
"""Test script to validate configuration parsing and key distribution logic."""

import os
import sys
sys.path.append('.')

def test_config_parsing():
    """Test the configuration parsing logic."""
    print("Testing configuration parsing...")
    
    try:
        from config import settings
        
        print(f"✓ XRAY_REALITY_SHORT_IDS: {settings.XRAY_REALITY_SHORT_IDS}")
        print(f"✓ XRAY_REALITY_PUBKEY: {settings.XRAY_REALITY_PUBKEY[:20]}..." if settings.XRAY_REALITY_PUBKEY else "✗ XRAY_REALITY_PUBKEY: None")
        print(f"✓ XRAY_PORT: {settings.XRAY_PORT}")
        print(f"✓ SERVER_IP: {settings.SERVER_IP}")
        print(f"✓ XRAY_REALITY_DEST: {settings.XRAY_REALITY_DEST}")
        
        return True
    except Exception as e:
        print(f"✗ Configuration parsing failed: {e}")
        return False

def test_reality_config():
    """Test the Reality configuration generation."""
    print("\nTesting Reality configuration generation...")
    
    try:
        from server_manager import ServerManager
        
        manager = ServerManager()
        config = manager.get_reality_config("test@example.com", "test-uuid-123")
        
        if config:
            print("✓ Reality config generated successfully:")
            print(f"  - Port: {config.get('port')}")
            print(f"  - SNI: {config.get('sni')}")
            print(f"  - Short ID: {config.get('sid')}")
            print(f"  - Public Key: {config.get('pbk', '')[:20]}...")
            return True
        else:
            print("✗ Reality config generation failed")
            return False
            
    except Exception as e:
        print(f"✗ Reality config generation failed: {e}")
        return False

def test_vless_url():
    """Test VLESS URL generation."""
    print("\nTesting VLESS URL generation...")
    
    try:
        from server_manager import ServerManager
        
        manager = ServerManager()
        url = manager.generate_vless_url("test@example.com", "test-uuid-123")
        
        if url:
            print("✓ VLESS URL generated successfully:")
            print(f"  URL: {url[:50]}...")
            
            # Check for common issues
            if 'sid=[' in url:
                print("✗ Found malformed short ID in URL (sid=[)")
                return False
            elif 'sid=' in url:
                print("✓ Short ID properly formatted in URL")
                
            return True
        else:
            print("✗ VLESS URL generation failed")
            return False
            
    except Exception as e:
        print(f"✗ VLESS URL generation failed: {e}")
        return False

if __name__ == "__main__":
    print("=== Xray Bot Configuration Test ===")
    
    success = True
    success &= test_config_parsing()
    success &= test_reality_config()
    success &= test_vless_url()
    
    print(f"\n=== Test Results ===")
    if success:
        print("✓ All tests passed!")
    else:
        print("✗ Some tests failed!")
    
    sys.exit(0 if success else 1)
