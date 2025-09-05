import grpc
import logging
from typing import List, Dict, Any, Optional
from concurrent import futures
import json
import uuid

# Import generated protobuf files
from app.xray_api.app.stats.command import command_pb2 as stats_command
from app.xray_api.app.stats.command import command_pb2_grpc as stats_service
from app.xray_api.app.proxyman.command import command_pb2 as proxyman_command
from app.xray_api.app.proxyman.command import command_pb2_grpc as proxyman_service
from app.xray_api.common.protocol import user_pb2 as user_protocol
from google.protobuf import empty_pb2

from config import XRAY_API_HOST, XRAY_API_PORT, XRAY_API_TAG, XRAY_REALITY_SHORT_IDS

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
            self.channel = grpc.insecure_channel(f"{XRAY_API_HOST}:{XRAY_API_PORT}")
            self.stats_stub = stats_service.StatsServiceStub(self.channel)
            self.handler_stub = proxyman_service.HandlerServiceStub(self.channel)
            
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
            user = user_protocol.User(
                level=level,
                email=email,
                account=user_protocol.Account(
                    type="vless",
                    settings=json.dumps({
                        "id": uuid_str,
                        "flow": "xtls-rprx-vision"
                    })
                )
            )
            
            # Add user to Xray
            request = proxyman_command.AddUserOperation(
                user=user
            )
            self.handler_stub.AlterInbound(proxyman_command.AlterInboundRequest(
                tag=XRAY_API_TAG,
                operation=request
            ))
            
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
            self.handler_stub.RemoveUser(proxyman_command.RemoveUserRequest(
                email=email
            ))
            
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
            
            # Get upload traffic
            upload_pattern = f"user>>>{email}>>>traffic>>>uplink" if email else "user>>>traffic>>>uplink"
            upload_request = stats_command.GetStatsRequest(
                name=upload_pattern,
                reset=reset
            )
            upload_response = self.stats_stub.GetStats(upload_request)
            
            # Get download traffic
            download_pattern = f"user>>>{email}>>>traffic>>>downlink" if email else "user>>>traffic>>>downlink"
            download_request = stats_command.GetStatsRequest(
                name=download_pattern,
                reset=reset
            )
            download_response = self.stats_stub.GetStats(download_request)
            
            # Process responses
            for stat in upload_response.stat:
                user = stat.name.split('>>>')[1]  # Extract username from pattern
                stats[user] = stats.get(user, {})
                stats[user]['upload'] = stat.value
                
            for stat in download_response.stat:
                user = stat.name.split('>>>')[1]  # Extract username from pattern
                stats[user] = stats.get(user, {})
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
            
            # Get system stats
            sys_stats = self.stats_stub.GetSysStats(empty_pb2.Empty())
            
            stats['num_goroutine'] = sys_stats.NumGoroutine
            stats['num_connection'] = sys_stats.NumGC
            stats['alloc'] = sys_stats.Alloc
            stats['total_alloc'] = sys_stats.TotalAlloc
            stats['sys'] = sys_stats.Sys
            stats['mallocs'] = sys_stats.Mallocs
            stats['frees'] = sys_stats.Frees
            stats['live_objects'] = sys_stats.Mallocs - sys_stats.Frees
            stats['pause_total_ns'] = sys_stats.PauseTotalNs
            stats['uptime'] = sys_stats.Uptime
            
            return stats
            
        except Exception as e:
            logger.error(f"Failed to get system stats: {e}")
            return {}
    
    def get_reality_short_ids(self) -> List[str]:
        """Get the list of valid Reality short IDs."""
        return XRAY_REALITY_SHORT_IDS
    
    def generate_reality_config(self, uuid_str: str, email: str) -> Dict[str, Any]:
        """Generate a Reality configuration for a user."""
        if not XRAY_REALITY_SHORT_IDS:
            logger.error("No Reality short IDs configured")
            return {}
            
        # Use the first short ID for now (could implement round-robin or other logic)
        short_id = XRAY_REALITY_SHORT_IDS[0]
        
        config = {
            "v": "2",
            "ps": f"Xray Reality - {email}",
            "add": SERVER_IP,
            "port": XRAY_PORT,
            "id": uuid_str,
            "scy": "chacha20-poly1305",
            "net": "tcp",
            "type": "none",
            "host": "",
            "path": "",
            "tls": "reality",
            "sni": XRAY_REALITY_DEST.split(':')[0],
            "alpn": "",
            "fp": "chrome",
            "pbk": XRAY_REALITY_PUBKEY,
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
