import os
import logging
import json
import subprocess
from typing import Dict, Any, Optional, List
from pathlib import Path
import grpc
import time
import uuid
import json
from typing import Optional, Dict, List, Tuple
import logging
from datetime import datetime, timedelta

from config import (
    XRAY_CONFIG_DIR, XRAY_CONFIG_FILE, XRAY_SERVICE,
    XRAY_REALITY_PRIVKEY, XRAY_REALITY_PUBKEY, XRAY_REALITY_SHORT_IDS,
    generate_xray_config
)

# Import generated gRPC code
import xray_api_pb2 as pb
import xray_api_pb2_grpc as pb_grpc

logger = logging.getLogger(__name__)

class XrayManager:
    """Manages Xray server operations using gRPC API."""
    
    def __init__(self, grpc_address: str = '127.0.0.1:50051'):
        """Initialize the Xray manager.
        
        Args:
            grpc_address: Address of the Xray gRPC API (default: 127.0.0.1:50051)
        """
        self.grpc_address = grpc_address
        self.channel = None
        self.stub = None
    
    def connect(self) -> bool:
        """Establish connection to Xray gRPC API.
        
        Returns:
            bool: True if connection was successful, False otherwise.
        """
        try:
            self.channel = grpc.insecure_channel(self.grpc_address)
            self.stub = pb_grpc.HandlerServiceStub(self.channel)
            return True
        except Exception as e:
            logger.error(f"Failed to connect to Xray gRPC API: {e}")
            return False
    
    def close(self):
        """Close the gRPC channel."""
        if self.channel:
            self.channel.close()
    
    def __enter__(self):
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
    
    def add_user(self, email: str, uuid_str: str, level: int = 0) -> bool:
        """Add a new user to Xray.
        
        Args:
            email: User's email (used as identifier)
            uuid_str: User's UUID
            level: User level (default: 0)
            
        Returns:
            bool: True if user was added successfully, False otherwise.
        """
        try:
            if not self.stub:
                self.connect()
                
            # Create user object
            user = pb.User(
                level=level,
                email=email,
                account=pb.Account(
                    type="vless",
                    settings=json.dumps({
                        "id": uuid_str,
                        "flow": "xtls-rprx-vision"
                    })
                )
            )
            
            # Add user
            response = self.stub.AddUser(pb.AddUserRequest(user=user))
            return response.success
            
        except grpc.RpcError as e:
            logger.error(f"gRPC error adding user {email}: {e.details()}")
            return False
        except Exception as e:
            logger.error(f"Error adding user {email}: {e}")
            return False
    
    def remove_user(self, email: str) -> bool:
        """Remove a user from Xray.
        
        Args:
            email: User's email to remove
            
        Returns:
            bool: True if user was removed successfully, False otherwise.
        """
        try:
            if not self.stub:
                self.connect()
                
            # Remove user
            response = self.stub.RemoveUser(pb.RemoveUserRequest(email=email))
            return response.success
            
        except grpc.RpcError as e:
            logger.error(f"gRPC error removing user {email}: {e.details()}")
            return False
        except Exception as e:
            logger.error(f"Error removing user {email}: {e}")
            return False
    
    def get_user_stats(self, email: str, reset: bool = False) -> Optional[Dict]:
        """Get user statistics.
        
        Args:
            email: User's email
            reset: Whether to reset the stats after retrieval
            
        Returns:
            Optional[Dict]: User statistics or None if failed
        """
        try:
            if not self.stub:
                self.connect()
                
            # Get user stats
            response = self.stub.GetUserStats(pb.GetUserStatsRequest(
                name=email,
                reset=reset
            ))
            
            return {
                'upload': response.upload,
                'download': response.download,
                'total': response.upload + response.download
            }
            
        except grpc.RpcError as e:
            logger.error(f"gRPC error getting stats for {email}: {e.details()}")
            return None
        except Exception as e:
            logger.error(f"Error getting stats for {email}: {e}")
            return None
    
    def get_system_stats(self) -> Optional[Dict]:
        """Get Xray system statistics.
        
        Returns:
            Optional[Dict]: System statistics or None if failed
        """
        try:
            if not self.stub:
                self.connect()
                
            # Get system stats
            response = self.stub.GetStats(pb.GetStatsRequest(
                name="",  # Empty name for system stats
                reset=False
            ))
            
            stats = {}
            for stat in response.stat:
                stats[stat.name] = stat.value
                
            return stats
            
        except grpc.RpcError as e:
            logger.error(f"gRPC error getting system stats: {e.details()}")
            return None
        except Exception as e:
            logger.error(f"Error getting system stats: {e}")
            return None
    
    def restart_xray(self) -> bool:
        """Restart Xray service.
        
        Returns:
            bool: True if restart was successful, False otherwise.
        """
        try:
            result = subprocess.run(
                ["systemctl", "restart", "xray"],
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
                ["systemctl", "is-active", "xray"],
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
            os.makedirs("/usr/local/etc/xray", exist_ok=True)
            
            # Write config file
            config_path = "/usr/local/etc/xray/config.json"
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
                ["journalctl", "-u", "xray", "-n", str(lines), "--no-pager"],
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
        return self.xray.add_user(email, uuid_str)
    
    def remove_vless_user(self, email: str) -> bool:
        """Remove a VLESS user.
        
        Args:
            email: User's email to remove
            
        Returns:
            bool: True if user was removed successfully, False otherwise.
        """
        return self.xray.remove_user(email)
        return self.xray_client.get_traffic_stats(email)
    
    def get_system_stats(self) -> Dict[str, Any]:
        """Get system statistics from Xray."""
        if not self.connected and not self.xray_client.connect():
            return {}
            
        return self.xray_client.get_system_stats()
    
    def get_reality_config(self, email: str, user_id: str) -> Dict[str, Any]:
        """Generate a Reality configuration for a user."""
        if not self.connected and not self.xray_client.connect():
            return {}
            
        return self.xray_client.generate_reality_config(user_id, email)
    
    def __del__(self):
        """Clean up resources."""
        if hasattr(self, 'xray_client') and self.xray_client:
            self.xray_client.close()

# Create a global server manager instance
server_manager = ServerManager()
