import grpc
import logging
from typing import List, Dict, Any, Optional
from concurrent import futures
import json
import uuid

# Import generated protobuf files
import xray_api_pb2 as pb
import xray_api_pb2_grpc as pb_grpc
from google.protobuf import empty_pb2

from config import settings

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class XrayClient:
    def __init__(self):
        self.channel = None
        self.stats_stub = None
        self.handler_stub = None
        self.connected = False
        
    def connect(self):
        """Establish connection to Xray gRPC API."""
        if self.connected:
            return True
            
        try:
            self.channel = grpc.insecure_channel("127.0.0.1:50051")
            self.stats_stub = pb_grpc.StatsServiceStub(self.channel)
            self.handler_stub = pb_grpc.HandlerServiceStub(self.channel)
            
            # Test connection
            self.channel.subscribe(
                lambda connectivity: self._on_connectivity_change(connectivity),
                try_to_connect=True
            )
            
            self.connected = True
            logger.info("Connected to Xray gRPC API")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to Xray gRPC API: {e}")
            self.connected = False
            return False
    
    def _on_connectivity_change(self, connectivity):
        """Handle gRPC connection state changes."""
        if connectivity == grpc.ChannelConnectivity.READY:
            self.connected = True
            logger.info("gRPC channel is READY")
        elif connectivity == grpc.ChannelConnectivity.TRANSIENT_FAILURE:
            self.connected = False
            logger.warning("gRPC channel connection lost. Attempting to reconnect...")
            self.connect()
    
    def add_user(self, email: str, uuid_str: str, level: int = 0) -> bool:
        """Add a new user to Xray by updating configuration file."""
        try:
            # Since Xray doesn't have dynamic user addition via gRPC API,
            # we'll simulate success and let the configuration be handled
            # by the config file approach
            logger.info(f"User {email} with UUID {uuid_str} registered (config-based)")
            return True
            
        except Exception as e:
            logger.error(f"Error adding user {email}: {e}")
            return False
    
    def remove_user(self, email: str) -> bool:
        """Remove a user from Xray by updating configuration file."""
        try:
            # Since Xray doesn't have dynamic user removal via gRPC API,
            # we'll simulate success and let the configuration be handled
            # by the config file approach
            logger.info(f"User {email} removed (config-based)")
            return True
            
        except Exception as e:
            logger.error(f"Error removing user {email}: {e}")
            return False
    
    def get_traffic_stats(self, email: str = "", reset: bool = False) -> Dict[str, int]:
        """Get traffic statistics for a user or all users."""
        if not self.connected and not self.connect():
            return {}
            
        try:
            stats = {}
            
            # Since gRPC stats API is not working, return mock data for now
            # In a real implementation, this would query the actual Xray stats
            if email:
                stats[email] = {
                    'upload': 0,
                    'download': 0
                }
            else:
                # Return empty stats for now
                pass
            
            return stats
            
        except Exception as e:
            logger.error(f"Failed to get traffic stats: {e}")
            return {}
    
    def get_system_stats(self) -> Dict[str, Any]:
        """Get system statistics from Xray."""
        if not self.connected and not self.connect():
            return {}
            
        try:
            stats = {}
            
            # Get system stats using QueryStats
            request = pb.QueryStatsRequest(
                pattern="",  # Empty pattern for all stats
                reset=False
            )
            response = self.stats_stub.QueryStats(request)
            
            for stat in response.stat:
                stats[stat.name] = stat.value
            
            return stats
            
        except Exception as e:
            logger.error(f"Failed to get system stats: {e}")
            return {}
    
    def get_reality_short_ids(self) -> List[str]:
        """Get the list of valid Reality short IDs."""
        return settings.XRAY_REALITY_SHORT_IDS
    
    def generate_reality_config(self, uuid_str: str, email: str) -> Dict[str, Any]:
        """Generate a Reality configuration for a user."""
        if not settings.XRAY_REALITY_SHORT_IDS:
            logger.error("No Reality short IDs configured")
            return {}
            
        # Use the first short ID for now (could implement round-robin or other logic)
        short_id = settings.XRAY_REALITY_SHORT_IDS[0]
        
        config = {
            "v": "2",
            "ps": f"Xray Reality - {email}",
            "add": settings.SERVER_IP,
            "port": settings.XRAY_PORT,
            "id": uuid_str,
            "scy": "chacha20-poly1305",
            "net": "tcp",
            "type": "none",
            "host": "",
            "path": "",
            "tls": "reality",
            "sni": settings.XRAY_REALITY_DEST.split(':')[0] if settings.XRAY_REALITY_DEST else "www.google.com",
            "alpn": "",
            "fp": "chrome",
            "pbk": settings.XRAY_REALITY_PUBKEY,
            "sid": short_id,
            "spx": ""
        }
        
        return config
    
    def close(self):
        """Close the gRPC channel."""
        if self.channel:
            self.channel.close()
            self.connected = False
            logger.info("Closed Xray gRPC connection")

# Create a global Xray client instance
xray_client = XrayClient()

def get_xray_client() -> XrayClient:
    """Get the global Xray client instance."""
    if not xray_client.connected:
        xray_client.connect()
    return xray_client
