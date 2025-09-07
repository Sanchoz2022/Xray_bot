#!/usr/bin/env python3
"""
Generate the correct public key for the private key in server config.
"""

import subprocess
import sys

def get_public_key_from_private(private_key):
    """Generate public key from private key using xray x25519 command."""
    try:
        # Use xray x25519 -i with private key as argument
        result = subprocess.run(
            ["/usr/local/bin/xray", "x25519", "-i", private_key],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print(f"Error running xray x25519: {result.stderr}")
            return None
        
        # Parse the output to extract public key
        lines = result.stdout.strip().split('\n')
        for line in lines:
            if 'Public key:' in line or 'PublicKey:' in line:
                return line.split(':')[1].strip()
        
        print(f"Could not find public key in output: {result.stdout}")
        return None
        
    except Exception as e:
        print(f"Exception generating public key: {e}")
        return None

if __name__ == "__main__":
    # Private key from server config
    private_key = "gD7Lz5CA00QLVoWU5Waqj6m_uYNwM1J42L9IA5CZgXw"
    
    print(f"Generating public key for private key: {private_key}")
    public_key = get_public_key_from_private(private_key)
    
    if public_key:
        print(f"Generated public key: {public_key}")
        print(f"\nUpdate .env file with:")
        print(f"XRAY_REALITY_PUBKEY={public_key}")
    else:
        print("Failed to generate public key")
        sys.exit(1)
