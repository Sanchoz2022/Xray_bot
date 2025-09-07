# Simplified gRPC stub implementation for Xray API
# This avoids the parsing issues with the generated protobuf files

import grpc
import xray_api_pb2 as pb

class HandlerServiceStub:
    """HandlerService handles user and system operations."""
    
    def __init__(self, channel):
        self.channel = channel
        
    def AddUser(self, request):
        """Add a user to the inbound handler."""
        # Mock implementation - returns success response
        return pb.AddUserResponse(success=True)
        
    def RemoveUser(self, request):
        """Remove a user from the inbound handler."""
        # Mock implementation - returns success response
        return pb.RemoveUserResponse(success=True)

class StatsServiceStub:
    """StatsService handles statistics operations."""
    
    def __init__(self, channel):
        self.channel = channel
        
    def GetUserStats(self, request):
        """Get user statistics."""
        # Mock implementation - returns zero stats
        return pb.GetUserStatsResponse(upload=0, download=0)
        
    def QueryStats(self, request):
        """Query system statistics."""
        # Mock implementation - returns empty stats
        return pb.QueryStatsResponse(stat=[])

