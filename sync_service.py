#!/usr/bin/env python3
"""
Automatic UUID synchronization service between Telegram bot and Xray server.
"""

import asyncio
import logging
from typing import Set, Dict, List
from datetime import datetime, timedelta
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from db import User, UserKey, async_session_maker
from server_manager import ServerManager
from config import settings

logger = logging.getLogger(__name__)

class XrayUserSyncService:
    """Service for automatic synchronization of users between bot DB and Xray server."""
    
    def __init__(self):
        self.server_manager = ServerManager()
        self.sync_interval = 300  # 5 minutes
        self.last_sync = None
        
    async def sync_user_on_action(self, user_id: int, action: str) -> bool:
        """
        Sync specific user immediately when action occurs.
        
        Args:
            user_id: Telegram user ID
            action: Action type ('create', 'renew', 'delete')
            
        Returns:
            bool: Success status
        """
        try:
            async with async_session_maker() as session:
                # Get user from database
                result = await session.execute(
                    select(User).where(User.telegram_id == user_id)
                )
                user = result.scalar_one_or_none()
                
                if not user:
                    logger.warning(f"User {user_id} not found in database")
                    return False
                
                # Get user keys separately
                keys_result = await session.execute(
                    select(UserKey).where(
                        UserKey.user_id == user.id,
                        UserKey.is_active == True
                    )
                )
                user_keys = keys_result.scalars().all()
                
                email = f"user_{user.id}@xray.com"
                
                if action == 'create':
                    return await self._ensure_user_exists(session, user, email, user_keys)
                elif action == 'renew':
                    return await self._renew_user_key(session, user, email, user_keys)
                elif action == 'delete':
                    return await self._remove_user(user, email)
                    
        except Exception as e:
            logger.error(f"Error syncing user {user_id} on {action}: {e}")
            return False
            
    async def _ensure_user_exists(self, session: AsyncSession, user: User, email: str, user_keys: List[UserKey]) -> bool:
        """Ensure user exists in Xray server."""
        try:
            # Get active key
            active_key = next((k for k in user_keys if k.is_active), None)
            if not active_key:
                logger.warning(f"No active key found for user {user.id}")
                return False
            
            # Check if user exists in Xray
            if not self.server_manager.add_vless_user(email, active_key.uuid):
                logger.error(f"Failed to add user {email} to Xray")
                return False
                
            logger.info(f"✅ User {email} synchronized with Xray")
            return True
            
        except Exception as e:
            logger.error(f"Error ensuring user exists: {e}")
            return False
    
    async def _renew_user_key(self, session: AsyncSession, user: User, email: str, user_keys: List[UserKey]) -> bool:
        """Renew user key in Xray server."""
        try:
            # Remove old user
            self.server_manager.remove_vless_user(email)
            
            # Add with new key
            active_key = next((k for k in user_keys if k.is_active), None)
            if active_key:
                success = self.server_manager.add_vless_user(email, active_key.uuid)
                if success:
                    logger.info(f"✅ User {email} key renewed in Xray")
                return success
            return False
            
        except Exception as e:
            logger.error(f"Error renewing user key: {e}")
            return False
    
    async def _remove_user(self, user: User, email: str) -> bool:
        """Remove user from Xray server."""
        try:
            success = self.server_manager.remove_vless_user(email)
            if success:
                logger.info(f"✅ User {email} removed from Xray")
            return success
            
        except Exception as e:
            logger.error(f"Error removing user: {e}")
            return False

    async def full_sync(self) -> Dict[str, int]:
        """
        Perform full synchronization between database and Xray server.
        
        Returns:
            Dict with sync statistics
        """
        stats = {'added': 0, 'removed': 0, 'errors': 0}
        
        try:
            async with async_session_maker() as session:
                # Get all users with active keys from database
                result = await session.execute(
                    select(User).join(UserKey).where(UserKey.is_active == True)
                )
                db_users = result.scalars().all()
                
                # Get all active keys
                keys_result = await session.execute(
                    select(UserKey).where(UserKey.is_active == True)
                )
                active_keys = {key.user_id: key for key in keys_result.scalars().all()}
                
                # Get current Xray users (would need to implement this in server_manager)
                xray_users = await self._get_xray_users()
                
                db_user_emails = set()
                
                # Sync database users to Xray
                for user in db_users:
                    active_key = active_keys.get(user.id)
                    if active_key:
                        email = f"user_{user.id}@xray.com"
                        db_user_emails.add(email)
                        
                        if email not in xray_users:
                            success = self.server_manager.add_vless_user(email, active_key.uuid)
                            if success:
                                stats['added'] += 1
                                logger.info(f"Added {email} to Xray")
                            else:
                                stats['errors'] += 1
                
                # Remove users from Xray that don't exist in database
                for xray_email in xray_users:
                    if xray_email not in db_user_emails:
                        success = self.server_manager.remove_vless_user(xray_email)
                        if success:
                            stats['removed'] += 1
                            logger.info(f"Removed {xray_email} from Xray")
                        else:
                            stats['errors'] += 1
                
                self.last_sync = datetime.now()
                logger.info(f"Full sync completed: {stats}")
                
        except Exception as e:
            logger.error(f"Error during full sync: {e}")
            stats['errors'] += 1
            
        return stats
    
    async def _get_xray_users(self) -> Set[str]:
        """Get list of users currently in Xray server."""
        # This would need to be implemented in server_manager
        # For now, return empty set
        return set()
    
    async def start_periodic_sync(self):
        """Start periodic synchronization task."""
        while True:
            try:
                await asyncio.sleep(self.sync_interval)
                await self.full_sync()
            except Exception as e:
                logger.error(f"Error in periodic sync: {e}")
                await asyncio.sleep(60)  # Wait 1 minute before retry

# Global sync service instance
sync_service = XrayUserSyncService()
