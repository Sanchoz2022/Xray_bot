import os
import logging
import json
import subprocess
from typing import Dict, Any, Optional, List
from pathlib import Path
import grpc
import time
import uuid
import base64
from typing import Optional, Dict, List, Tuple
import logging
from datetime import datetime, timedelta
from urllib.parse import quote

from config import settings, generate_xray_config
from xray_grpc import get_xray_client

logger = logging.getLogger(__name__)

class XrayManager:
    """Manages Xray server operations using gRPC API."""
    
    def __init__(self, grpc_address: str = '127.0.0.1:50051'):
        """Initialize the Xray manager.
        
        Args:
            grpc_address: Address of the Xray gRPC API (default: 127.0.0.1:50051)
        """
        self.grpc_address = grpc_address
        self.xray_client = get_xray_client()
    
    def connect(self) -> bool:
        """Establish connection to Xray gRPC API.
        
        Returns:
            bool: True if connection was successful, False otherwise.
        """
        return self.xray_client.connect()
    
    def close(self):
        """Close the gRPC channel."""
        self.xray_client.close()
    
    def __enter__(self):
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
    
    def add_user(self, email: str, uuid_str: str, level: int = 0) -> bool:
        """Add a new user to Xray using gRPC API.
        
        Args:
            email: User's email (used as identifier)
            uuid_str: User's UUID
            level: User level (default: 0)
            
        Returns:
            bool: True if user was added successfully, False otherwise.
        """
        return self.xray_client.add_user(email, uuid_str, level)
    
    def remove_user(self, email: str) -> bool:
        """Remove a user from Xray using gRPC API.
        
        Args:
            email: User's email to remove
            
        Returns:
            bool: True if user was removed successfully, False otherwise.
        """
        return self.xray_client.remove_user(email)
    
    def get_user_stats(self, email: str, reset: bool = False) -> Optional[Dict]:
        """Get user statistics using gRPC API.
        
        Args:
            email: User's email
            reset: Whether to reset the stats after retrieval
            
        Returns:
            Optional[Dict]: User statistics or None if failed
        """
        try:
            stats = self.xray_client.get_traffic_stats(email, reset)
            if email in stats:
                user_stats = stats[email]
                return {
                    'upload': user_stats.get('upload', 0),
                    'download': user_stats.get('download', 0),
                    'total': user_stats.get('upload', 0) + user_stats.get('download', 0)
                }
            return None
        except Exception as e:
            logger.error(f"Error getting stats for {email}: {e}")
            return None
    
    def get_system_stats(self) -> Optional[Dict]:
        """Get Xray system statistics.
        
        Returns:
            Optional[Dict]: System statistics or None if failed
        """
        return self.xray_client.get_system_stats()
    
    def restart_xray(self) -> bool:
        """Restart Xray service.
        
        Returns:
            bool: True if restart was successful, False otherwise.
        """
        try:
            result = subprocess.run(
                ["/usr/bin/systemctl", "restart", settings.XRAY_SERVICE],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Failed to restart Xray: {result.stderr}")
                return False
                
            # Wait a bit for Xray to restart
            time.sleep(2)
            return True
            
        except Exception as e:
            logger.error(f"Error restarting Xray: {e}")
            return False
    
    def get_xray_status(self) -> Dict:
        """Get Xray service status.
        
        Returns:
            Dict: Status information
        """
        status = {
            'installed': False,
            'running': False,
            'version': None,
            'error': None
        }
        
        try:
            # Check if Xray is installed
            result = subprocess.run(
                ["which", "xray"],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                status['error'] = 'Xray is not installed'
                return status
            
            # Get Xray version
            result = subprocess.run(
                ["xray", "-version"],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                status['version'] = result.stdout.split('\n')[0]
                status['installed'] = True
            
            # Check if Xray is running
            result = subprocess.run(
                ["/usr/bin/systemctl", "is-active", settings.XRAY_SERVICE],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                status['running'] = True
            
            return status
            
        except Exception as e:
            status['error'] = str(e)
            return status


class ServerManager:
    """Handles server management operations including Xray installation and configuration."""
    
    def __init__(self, grpc_address: str = '127.0.0.1:50051'):
        """Initialize the server manager.
        
        Args:
            grpc_address: Address of the Xray gRPC API (default: 127.0.0.1:50051)
        """
        self.grpc_address = grpc_address
        self.xray = XrayManager(grpc_address)
    
    def install_xray(self) -> bool:
        """Install Xray on the server.
        
        Returns:
            bool: True if installation was successful, False otherwise.
        """
        try:
            # Install Xray using the official installation script
            install_cmd = "bash -c \"$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\""
            
            result = subprocess.run(
                install_cmd, 
                shell=True, 
                capture_output=True, 
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Failed to install Xray: {result.stderr}")
                return False
            
            logger.info("Xray installed successfully")
            logger.debug(f"Installation output: {result.stdout}")
            return True
            
        except Exception as e:
            logger.error(f"Error installing Xray: {e}")
            return False
    
    def configure_xray(self, config: Dict) -> bool:
        """Configure Xray with the provided configuration.
        
        Args:
            config: Dictionary containing Xray configuration.
            
        Returns:
            bool: True if configuration was successful, False otherwise.
        """
        try:
            import os
            
            # Create config directory if it doesn't exist
            os.makedirs(settings.XRAY_CONFIG_DIR, exist_ok=True)
            
            # Write config file
            config_path = settings.XRAY_CONFIG_FILE
            with open(config_path, 'w') as f:
                json.dump(config, f, indent=2)
            
            # Set proper permissions
            os.chmod(config_path, 0o600)
            os.chown(config_path, 0, 0)  # root:root
            
            # Create log directory
            os.makedirs("/var/log/xray", exist_ok=True)
            for log_file in ["access.log", "error.log"]:
                log_path = f"/var/log/xray/{log_file}"
                if not os.path.exists(log_path):
                    open(log_path, 'a').close()
                os.chmod(log_path, 0o600)
                os.chown(log_path, 0, 0)
            
            logger.info("Xray configuration updated successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error configuring Xray: {e}")
            return False
    
    def restart_xray(self) -> bool:
        """Restart the Xray service.
        
        Returns:
            bool: True if restart was successful, False otherwise.
        """
        return self.xray.restart_xray()
    
    def get_xray_status(self) -> Dict:
        """Get the status of the Xray service.
        
        Returns:
            Dict: Status information.
        """
        return self.xray.get_xray_status()
    
    def get_xray_logs(self, lines: int = 50) -> str:
        """Get the last N lines of Xray logs.
        
        Args:
            lines: Number of lines to retrieve.
            
        Returns:
            str: The log content.
        """
        try:
            result = subprocess.run(
                ["/usr/bin/journalctl", "-u", settings.XRAY_SERVICE, "-n", str(lines), "--no-pager"],
                capture_output=True,
                text=True
            )
            return result.stdout if result.returncode == 0 else result.stderr
                
        except Exception as e:
            return f"Error retrieving logs: {e}"
    
    def add_vless_user(self, email: str, uuid_str: str) -> bool:
        """Add a new VLESS user.
        
        Args:
            email: User's email (used as identifier)
            uuid_str: User's UUID
            
        Returns:
            bool: True if user was added successfully, False otherwise.
        """
        try:
            # Ensure connection is established
            if not self.xray.connect():
                logger.error("Failed to connect to Xray gRPC API")
                return False
            
            result = self.xray.add_user(email, uuid_str)
            if result:
                logger.info(f"Successfully added VLESS user {email} with UUID {uuid_str}")
            else:
                logger.error(f"Failed to add VLESS user {email}")
            
            return result
            
        except Exception as e:
            logger.error(f"Error adding VLESS user {email}: {e}")
            return False
    
    def remove_vless_user(self, email: str) -> bool:
        """Remove a VLESS user.
        
        Args:
            email: User's email to remove
            
        Returns:
            bool: True if user was removed successfully, False otherwise.
        """
        try:
            # Ensure connection is established
            if not self.xray.connect():
                logger.error("Failed to connect to Xray gRPC API")
                return False
            
            result = self.xray.remove_user(email)
            if result:
                logger.info(f"Successfully removed VLESS user {email}")
            else:
                logger.error(f"Failed to remove VLESS user {email}")
            
            return result
            
        except Exception as e:
            logger.error(f"Error removing VLESS user {email}: {e}")
            return False
    
    def get_system_stats(self) -> Dict[str, Any]:
        """Get system statistics from Xray."""
        return self.xray.get_system_stats() if hasattr(self.xray, 'get_system_stats') else {}
    
    def get_reality_config(self, email: str, user_id: str) -> Dict[str, Any]:
        """Generate a complete VLESS Reality configuration for a user."""
        try:
            if not settings.XRAY_REALITY_SHORT_IDS:
                logger.error("No Reality short IDs configured")
                return {}
            
            # Use the first short ID
            short_id = settings.XRAY_REALITY_SHORT_IDS[0]
            
            # Generate complete VLESS Reality config
            config = {
                "v": "2",
                "ps": f"Xray Reality - {email}",
                "add": getattr(settings, 'SERVER_IP', '127.0.0.1'),
                "port": getattr(settings, 'XRAY_PORT', 443),
                "id": user_id,
                "aid": "0",
                "scy": "auto",
                "net": "tcp",
                "type": "none",
                "host": "",
                "path": "",
                "tls": "reality",
                "sni": getattr(settings, 'XRAY_REALITY_DEST', 'www.google.com').split(':')[0],
                "alpn": "",
                "fp": "chrome",
                "pbk": settings.XRAY_REALITY_PUBKEY,
                "sid": short_id,
                "spx": "",
                "flow": "xtls-rprx-vision"
            }
            
            return config
            
        except Exception as e:
            logger.error(f"Error generating Reality config: {e}")
            return {}
    
    def generate_vless_url(self, email: str, user_id: str) -> str:
        """Generate a complete VLESS Reality URL for the user."""
        try:
            config = self.get_reality_config(email, user_id)
            if not config:
                return ""
            
            # Build VLESS URL
            vless_url = (
                f"vless://{config['id']}@{config['add']}:{config['port']}"
                f"?encryption=none&flow={config['flow']}&security={config['tls']}"
                f"&sni={config['sni']}&fp={config['fp']}&pbk={config['pbk']}"
                f"&sid={config['sid']}&type={config['net']}"
                f"#{config['ps']}"
            )
            
            return vless_url
            
        except Exception as e:
            logger.error(f"Error generating VLESS URL: {e}")
            return ""
    
    def __del__(self):
        """Clean up resources."""
        if hasattr(self, 'xray') and self.xray:
            self.xray.close()

# Create a global server manager instance
server_manager = ServerManager()
