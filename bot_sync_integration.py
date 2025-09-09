#!/usr/bin/env python3
"""
Integration of sync service with bot handlers.
"""

from sync_service import sync_service
import logging

logger = logging.getLogger(__name__)

# Decorator for automatic sync on user actions
def sync_on_action(action_type: str):
    """Decorator to automatically sync user after bot action."""
    def decorator(func):
        import functools
        
        @functools.wraps(func)
        async def wrapper(*args, **kwargs):
            # Execute original function first
            result = await func(*args, **kwargs)
            
            # Extract user_id from callback or message
            user_id = None
            if args and hasattr(args[0], 'from_user'):
                user_id = args[0].from_user.id
            elif args and hasattr(args[0], 'message') and hasattr(args[0].message, 'from_user'):
                user_id = args[0].message.from_user.id
            
            # Perform sync if user_id found
            if user_id:
                try:
                    await sync_service.sync_user_on_action(user_id, action_type)
                    logger.info(f"✅ Sync completed for user {user_id} on {action_type}")
                except Exception as e:
                    logger.error(f"❌ Sync failed for user {user_id} on {action_type}: {e}")
            
            return result
        return wrapper
    return decorator

# Modified bot handlers with sync integration
"""
Usage in bot.py:

from bot_sync_integration import sync_on_action

@sync_on_action('create')
async def check_subscription_callback(callback: CallbackQuery, session: AsyncSession):
    # Original handler code...
    pass

@sync_on_action('renew') 
async def renew_callback(callback: CallbackQuery, session: AsyncSession):
    # Original handler code...
    pass

@sync_on_action('delete')
async def remove_user_handler(callback: CallbackQuery, session: AsyncSession):
    # Original handler code...
    pass
"""
