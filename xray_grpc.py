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
        """Add a new user to Xray."""
        if not self.connected and not self.connect():
            return False
            
        try:
            # Create user
            account = pb.Account(
                type="vless",
                settings=json.dumps({
                    "id": uuid_str,
                    "flow": "xtls-rprx-vision"
                })
            )
            
            user = pb.User(
                level=level,
                email=email,
                account=account
            )
            
            # Add user to Xray
            request = pb.AddUserRequest(
                user=user
            )
            self.handler_stub.AddUser(request)
            
            logger.info(f"Added user {email} with UUID {uuid_str}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add user {email}: {e}")
            return False
    
    def remove_user(self, email: str) -> bool:
        """Remove a user from Xray."""
        if not self.connected and not self.connect():
            return False
            
        try:
            # Remove user from Xray
            request = pb.RemoveUserRequest(
                email=email
            )
            self.handler_stub.RemoveUser(request)
            
            logger.info(f"Removed user {email}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to remove user {email}: {e}")
            return False
    
    def get_traffic_stats(self, email: str = "", reset: bool = False) -> Dict[str, int]:
        """Get traffic statistics for a user or all users."""
        if not self.connected and not self.connect():
            return {}
            
        try:
            stats = {}
            
            # Get user stats using QueryStats
            pattern = f"user>>>{email}>>>traffic>>>" if email else "user>>>traffic>>>"
            request = pb.QueryStatsRequest(
                pattern=pattern,
                reset=reset
            )
            response = self.stats_stub.QueryStats(request)
            
            # Process responses
            for stat in response.stat:
                if ">>>" in stat.name:
                    parts = stat.name.split('>>>')
                    if len(parts) >= 2:
                        user = parts[1]  # Extract username from pattern
                        stats[user] = stats.get(user, {})
                        if "uplink" in stat.name:
                            stats[user]['upload'] = stat.value
                        elif "downlink" in stat.name:
                            stats[user]['download'] = stat.value
            
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
            "spx": "",
            "flow": "xtls-rprx-vision"
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
