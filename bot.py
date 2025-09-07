import os
import logging
import asyncio
import json
import uuid
from datetime import datetime, timedelta
from typing import Dict, Optional, Any, List, Tuple

from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import Command, CommandStart
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery, FSInputFile
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.utils.keyboard import InlineKeyboardBuilder
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select, update, delete, func
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from db import db, User, UserKey, Subscription, get_db_session, async_session_maker
from server_manager import server_manager, ServerManager

# Initialize server manager
server_manager = ServerManager()

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize bot and dispatcher with timeout settings
from aiohttp import ClientTimeout
bot = Bot(token=settings.BOT_TOKEN, timeout=ClientTimeout(total=30, connect=10))
dp = Dispatcher()

# Scheduler for background tasks
scheduler = AsyncIOScheduler()

# States
class UserState(StatesGroup):
    waiting_for_domain = State()
    waiting_for_email = State()

# Database helper functions
async def get_user(session: AsyncSession, user_id: int) -> User:
    """Get user by telegram_id."""
    result = await session.execute(
        select(User).where(User.telegram_id == user_id)
    )
    return result.scalar_one_or_none()

async def get_active_subscription(session: AsyncSession, user_id: int) -> Subscription:
    """Get active subscription for user."""
    result = await session.execute(
        select(Subscription)
        .join(User, Subscription.user_id == User.id)
        .where(User.telegram_id == user_id)
        .where(Subscription.is_active == True)
    )
    return result.scalar_one_or_none()

async def init_db():
    """Initialize database tables."""
    from db import Base, engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

# Helper functions
async def check_subscription(user_id: int, channel_username: str) -> bool:
    """Check if user is subscribed to the channel.
    
    Args:
        user_id: Telegram user ID
        channel_username: Channel username with @
        
    Returns:
        bool: True if user is subscribed, False otherwise
    """
    try:
        if not channel_username:
            logger.warning("No channel username provided for subscription check")
            return True  # If no channel is set, consider user subscribed
            
        # Remove @ if present
        channel_username = channel_username.lstrip('@')
        
        member = await bot.get_chat_member(
            chat_id=f"@{channel_username}",
            user_id=user_id
        )
        return member.status in ['member', 'administrator', 'creator']
    except Exception as e:
        logger.error(f"Error checking subscription for user {user_id} in channel {channel_username}: {e}")
        return False  # On error, assume not subscribed to prevent unauthorized access

def generate_reality_config(uuid_str: str, email: str = "", server_ip: str = "", public_key: str = "", short_id: str = "") -> Dict[str, str]:
    """Generate Reality configuration for the user.
    
    Args:
        uuid_str: User's UUID
        email: User's email (optional)
        server_ip: Server IP address
        public_key: Xray public key
        short_id: Short ID for Reality
        
    Returns:
        Dict with configuration details
    """
    if not public_key or not short_id or not server_ip:
        logger.error("Missing required parameters for Reality config")
        return {}
    
    # Generate the VLESS URL with Reality transport
    vless_url = (
        f"vless://{uuid_str}@{server_ip}:443?type=tcp&encryption=none&"
        f"security=reality&sni=www.google.com&fp=chrome&pbk={public_key}&"
        f"sid={short_id}&flow=xtls-rprx-vision#Xray-Reality-{email}"
    )
    
    # Generate QR code data
    qr_data = vless_url
    
    return {
        'vless_url': vless_url,
        'qr_data': qr_data,
        'config': {
            'v': '2',
            'ps': f'Xray Reality - {email}',
            'add': server_ip,
            'port': '443',
            'id': uuid_str,
            'type': 'tcp',
            'security': 'reality',
            'sni': 'www.google.com',
            'fp': 'chrome',
            'pbk': public_key,
            'sid': short_id,
            'flow': 'xtls-rprx-vision'
        }
    }

def format_bytes(size: int) -> str:
    """Format bytes to human-readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024.0:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{size:.2f} PB"

# Command handlers
@dp.message(CommandStart())
async def cmd_start(message: Message):
    """Handle /start command."""
    user = message.from_user
    
    # Add user to database
    async with async_session_maker() as session:
        user_result = await session.execute(
            select(User).where(User.telegram_id == user.id)
        )
        db_user = user_result.scalar_one_or_none()
        
        if not db_user:
            db_user = User(
                telegram_id=user.id,
                username=user.username,
                full_name=f"{user.first_name or ''} {user.last_name or ''}".strip()
            )
            session.add(db_user)
            await session.commit()
    
    # Check subscription
    is_subscribed = await check_subscription(user.id, settings.CHANNEL_USERNAME)
    
    # Create welcome message
    text = (
        f"👋 Привет, {user.first_name}!\n\n"
        "Это бот для настройки и управления VPN-сервером Xray с поддержкой Reality.\n\n"
        "📡 Для начала работы подпишитесь на наш канал и нажмите кнопку ниже:"
    )
    
    # Create keyboard
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📢 Подписаться на канал", url=f"https://t.me/{settings.CHANNEL_USERNAME.lstrip('@')}")],
        [InlineKeyboardButton(text="✅ Проверить подписку", callback_data="check_subscription")],
        [InlineKeyboardButton(text="📊 Статистика", callback_data="user_stats")]
    ])
    
    await message.answer(text, reply_markup=keyboard)

@dp.callback_query(F.data == "check_subscription")
async def check_subscription_callback(callback: CallbackQuery):
    """Handle subscription check callback."""
    user = callback.from_user
    is_subscribed = await check_subscription(user.id, settings.CHANNEL_USERNAME)
    
    if not is_subscribed:
        await callback.answer("❌ Вы не подписаны на канал. Пожалуйста, подпишитесь и попробуйте снова.", show_alert=True)
        return
    
    try:
        async with async_session_maker() as session:
            # Update subscription status
            user_result = await session.execute(
                select(User).where(User.telegram_id == user.id)
            )
            db_user = user_result.scalar_one_or_none()
            
            if not db_user:
                await callback.answer("❌ Пользователь не найден. Пожалуйста, начните с /start", show_alert=True)
                return
                
            # Get or create user key
            key_result = await session.execute(
                select(UserKey).where(
                    UserKey.user_id == db_user.id,
                    UserKey.is_active == True
                )
            )
            key = key_result.scalar_one_or_none()
            
            if not key:
                # Generate new UUID for the user
                user_uuid = str(uuid.uuid4())
                
                # Add user to Xray via gRPC
                if not server_manager.add_vless_user(email=f"user_{user.id}@xray.com", uuid_str=user_uuid):
                    await callback.answer("❌ Ошибка при настройке VPN. Пожалуйста, попробуйте позже.", show_alert=True)
                    return
                
                # Create new key in database
                key = UserKey(
                    user_id=db_user.id,
                    uuid=user_uuid,
                    is_active=True,
                    created_at=datetime.utcnow(),
                    expires_at=datetime.utcnow() + timedelta(days=30)  # 30 days validity
                )
                session.add(key)
                await session.commit()
            
            # Generate VLESS Reality URL
            vless_url = server_manager.generate_vless_url(f"user_{user.id}@xray.com", key.uuid)
            
            if not vless_url:
                await callback.answer("❌ Ошибка при генерации конфигурации. Пожалуйста, попробуйте позже.", show_alert=True)
                return
            
            # Create response message
            text = (
                "🎉 *Ваш VLESS Reality конфиг готов!*\n\n"
                "🔑 *Протокол:* `VLESS`\n"
                "🌐 *Адрес:* `{0}`\n"
                "🔌 *Порт:* `443`\n"
                "🆔 *UUID:* `{1}`\n"
                "🔒 *Шифрование:* `none`\n"
                "🚀 *Транспорт:* `TCP + Reality`\n"
                "🌊 *Flow:* `xtls-rprx-vision`\n\n"
                "📱 *Как использовать:*\n"
                "1. Скачайте v2rayNG (Android) или v2rayN (Windows)\n"
                "2. Нажмите кнопку ниже для копирования VLESS URL\n"
                "3. Импортируйте URL в приложение\n"
                "4. Подключитесь к серверу\n\n"
                "⚡ *Статус:* Активен до {2}"
            ).format(
                getattr(settings, 'SERVER_IP', '127.0.0.1'), 
                key.uuid,
                key.expires_at.strftime('%d.%m.%Y') if key.expires_at else 'Не ограничено'
            )
            
            # Create keyboard
            keyboard = InlineKeyboardBuilder()
            keyboard.row(
                InlineKeyboardButton(
                    text="📋 Скопировать VLESS URL",
                    callback_data=f"copy_vless_{key.id}"
                )
            )
            keyboard.row(
                InlineKeyboardButton(
                    text="📊 Статистика",
                    callback_data=f"stats_{key.id}"
                ),
                InlineKeyboardButton(
                    text="🔄 Обновить ключ",
                    callback_data=f"renew_{key.id}"
                )
            )
            keyboard.row(
                InlineKeyboardButton(
                    text="🔙 Назад",
                    callback_data="main_menu"
                )
            )
            
            # Store VLESS URL for copying
            setattr(key, '_vless_url', vless_url)
            
            await callback.message.edit_text(
                text,
                reply_markup=keyboard.as_markup(),
                parse_mode="Markdown"
            )
            
    except Exception as e:
        logger.error(f"Error in subscription callback: {e}", exc_info=True)
        await callback.answer("❌ Произошла ошибка. Пожалуйста, попробуйте позже.", show_alert=True)

@dp.callback_query(F.data.startswith("copy_vless_"))
async def copy_vless_callback(callback: CallbackQuery):
    """Handle copy VLESS URL callback."""
    try:
        key_id = int(callback.data.split("_")[-1])
        
        async with async_session_maker() as session:
            # Get the user key
            key_result = await session.execute(
                select(UserKey).where(
                    UserKey.id == key_id,
                    UserKey.is_active == True
                )
            )
            key = key_result.scalar_one_or_none()
            
            if not key:
                await callback.answer("❌ Ключ не найден или неактивен.", show_alert=True)
                return
            
            # Get user info
            user_result = await session.execute(
                select(User).where(User.id == key.user_id)
            )
            user = user_result.scalar_one_or_none()
            
            if not user:
                await callback.answer("❌ Пользователь не найден.", show_alert=True)
                return
            
            # Generate VLESS URL
            vless_url = server_manager.generate_vless_url(f"user_{user.id}@xray.com", key.uuid)
            
            if not vless_url:
                await callback.answer("❌ Ошибка при генерации VLESS URL.", show_alert=True)
                return
            
            # Send VLESS URL as a message that can be copied
            await callback.message.reply(
                f"📋 **VLESS URL для копирования:**\n\n`{vless_url}`\n\n"
                "💡 *Нажмите на URL выше, чтобы скопировать его*",
                parse_mode="Markdown"
            )
            
            await callback.answer("✅ VLESS URL отправлен!")
            
    except Exception as e:
        logger.error(f"Error in copy VLESS callback: {e}", exc_info=True)
        await callback.answer("❌ Произошла ошибка при копировании.", show_alert=True)

@dp.callback_query(F.data.startswith("stats_"))
async def stats_callback(callback: CallbackQuery):
    """Handle stats callback."""
    try:
        key_id = int(callback.data.split("_")[-1])
        
        async with async_session_maker() as session:
            # Get the user key
            key_result = await session.execute(
                select(UserKey).where(
                    UserKey.id == key_id,
                    UserKey.is_active == True
                )
            )
            key = key_result.scalar_one_or_none()
            
            if not key:
                await callback.answer("❌ Ключ не найден или неактивен.", show_alert=True)
                return
            
            # Get user info
            user_result = await session.execute(
                select(User).where(User.id == key.user_id)
            )
            user = user_result.scalar_one_or_none()
            
            if not user:
                await callback.answer("❌ Пользователь не найден.", show_alert=True)
                return
            
            # Get stats from Xray
            stats = server_manager.xray.get_user_stats(f"user_{user.id}@xray.com")
            
            if stats:
                upload_gb = stats.get('upload', 0) / (1024**3)
                download_gb = stats.get('download', 0) / (1024**3)
                total_gb = stats.get('total', 0) / (1024**3)
                
                stats_text = (
                    f"📊 **Статистика использования**\n\n"
                    f"📤 **Отправлено:** {upload_gb:.2f} GB\n"
                    f"📥 **Получено:** {download_gb:.2f} GB\n"
                    f"📊 **Всего:** {total_gb:.2f} GB\n\n"
                    f"⏰ **Активен до:** {key.expires_at.strftime('%d.%m.%Y %H:%M') if key.expires_at else 'Не ограничено'}\n"
                    f"🆔 **UUID:** `{key.uuid}`"
                )
            else:
                stats_text = (
                    "📊 **Статистика использования**\n\n"
                    "❌ Не удалось получить статистику.\n"
                    "Возможно, соединение с сервером еще не было установлено.\n\n"
                    f"⏰ **Активен до:** {key.expires_at.strftime('%d.%m.%Y %H:%M') if key.expires_at else 'Не ограничено'}\n"
                    f"🆔 **UUID:** `{key.uuid}`"
                )
            
            await callback.message.reply(stats_text, parse_mode="Markdown")
            await callback.answer("📊 Статистика обновлена!")
            
    except Exception as e:
        logger.error(f"Error in stats callback: {e}", exc_info=True)
        await callback.answer("❌ Произошла ошибка при получении статистики.", show_alert=True)

@dp.callback_query(F.data.startswith("renew_"))
async def renew_callback(callback: CallbackQuery):
    """Handle renew key callback."""
    try:
        key_id = int(callback.data.split("_")[-1])
        
        async with async_session_maker() as session:
            # Get the user key
            key_result = await session.execute(
                select(UserKey).where(
                    UserKey.id == key_id,
                    UserKey.is_active == True
                )
            )
            key = key_result.scalar_one_or_none()
            
            if not key:
                await callback.answer("❌ Ключ не найден или неактивен.", show_alert=True)
                return
            
            # Get user info
            user_result = await session.execute(
                select(User).where(User.id == key.user_id)
            )
            user = user_result.scalar_one_or_none()
            
            if not user:
                await callback.answer("❌ Пользователь не найден.", show_alert=True)
                return
            
            # Remove old user from Xray
            server_manager.remove_vless_user(f"user_{user.id}@xray.com")
            
            # Generate new UUID
            new_uuid = str(uuid.uuid4())
            
            # Add new user to Xray
            if not server_manager.add_vless_user(f"user_{user.id}@xray.com", new_uuid):
                await callback.answer("❌ Ошибка при обновлении ключа.", show_alert=True)
                return
            
            # Update key in database
            key.uuid = new_uuid
            key.created_at = datetime.utcnow()
            key.expires_at = datetime.utcnow() + timedelta(days=30)
            key.used_bytes = 0
            
            await session.commit()
            
            # Generate new VLESS URL
            vless_url = server_manager.generate_vless_url(f"user_{user.id}@xray.com", new_uuid)
            
            renewal_text = (
                "🔄 **Ключ успешно обновлен!**\n\n"
                f"🆔 **Новый UUID:** `{new_uuid}`\n"
                f"⏰ **Активен до:** {key.expires_at.strftime('%d.%m.%Y %H:%M')}\n\n"
                "📋 **Новый VLESS URL:**\n\n"
                f"`{vless_url}`\n\n"
                "💡 *Нажмите на URL выше, чтобы скопировать его*"
            )
            
            await callback.message.reply(renewal_text, parse_mode="Markdown")
            await callback.answer("✅ Ключ обновлен!")
            
    except Exception as e:
        logger.error(f"Error in renew callback: {e}", exc_info=True)
        await callback.answer("❌ Произошла ошибка при обновлении ключа.", show_alert=True)

@dp.callback_query(F.data.startswith("copy_config_"))
async def copy_config_callback(callback: CallbackQuery):
    """Handle copy config callback (legacy)."""
    try:
        key_id = int(callback.data.replace("copy_config_", ""))
        user_id = callback.from_user.id
        
        async with async_session_maker() as session:
            # Get user's active subscription
            subscription = await get_active_subscription(session, user_id)
            if not subscription:
                await callback.answer("❌ У вас нет активной подписки", show_alert=True)
                return
                
            # Get user data
            user = await get_user(session, user_id)
            if not user:
                await callback.answer("❌ Пользователь не найден", show_alert=True)
                return
            
            # Generate config
            config = generate_reality_config(
                str(uuid.uuid4()),  # Generate new UUID for security
                user.email or "",
                settings.SERVER_IP,
                settings.XRAY_REALITY_PUBKEY,
                settings.XRAY_REALITY_SHORT_IDS[0] if settings.XRAY_REALITY_SHORT_IDS else ""
            )
            
            if not config:
                await callback.answer("❌ Ошибка генерации конфигурации", show_alert=True)
                return
                
            # Copy to clipboard and show confirmation
            await callback.answer("✅ Конфиг скопирован в буфер обмена", show_alert=True)
            
            # Send instructions
            await callback.message.answer(
                '📱 *Инструкция по настройке:*\n\n'
                '1. Скачайте приложение Xray для вашего устройства\n'
                '2. Откройте приложение и нажмите "Добавить конфигурацию"\n'
                '3. Вставьте скопированный URL и сохраните\n'
                '4. Активируйте соединение\n\n'
                '⚠️ *Внимание:* Не передавайте этот конфиг третьим лицам!',
                parse_mode="Markdown"
            )
            
            # Send the config as a message
            config_text = f'```\n{config["vless_url"]}\n```'
            await callback.message.answer(
                config_text,
                parse_mode="Markdown"
            )
            
    except Exception as e:
        logger.error(f"Error in copy_config_callback: {e}", exc_info=True)
        await callback.answer("❌ Произошла ошибка. Пожалуйста, попробуйте позже.", show_alert=True)

@dp.message(Command("help"))
async def cmd_help(message: Message):
    """Handle /help command."""
    help_text = (
        "🤖 *Xray VPN Bot*\n\n"
        "Доступные команды:\n"
        "/start` - Начать работу с ботом\n"
        "/help` - Показать это сообщение\n"
        "/status` - Показать статус вашей подписки\n"
        "\nЕсли у вас возникли вопросы, обратитесь к администратору."
    )
    
    await message.answer(help_text, parse_mode="Markdown")

@dp.message(Command("status"))
async def cmd_status(message: Message):
    """Handle /status command."""
    user_id = message.from_user.id
    
    # Get user data from database
    async with async_session_maker() as session:
        user = await get_user(session, user_id)
        if not user:
            await message.answer("❌ Пользователь не найден. Пожалуйста, начните с команды /start")
            return
            
        subscription = await get_active_subscription(session, user_id)
        is_subscribed = await check_subscription(user_id, settings.CHANNEL_USERNAME)
    
    if not is_subscribed:
        text = "❌ Ваша подписка не активна. Пожалуйста, подпишитесь на канал и попробуйте снова."
    elif not subscription:
        text = "❌ У вас нет активной подписки. Пожалуйста, нажмите /start для активации."
    else:
        expires_at = subscription.end_date.strftime("%d.%m.%Y %H:%M")
        data_used = subscription.data_used / (1024 ** 3)  # Convert to GB
        data_limit = subscription.data_limit / (1024 ** 3)  # Convert to GB
        data_remaining = subscription.data_remaining / (1024 ** 3)  # Convert to GB
        
        text = (
            "📊 *Статус вашей подписки*\n\n"
            f"👤 Пользователь: `{user.full_name or user.telegram_id}`\n"
            f"📅 Истекает: `{expires_at}`\n"
            f"📊 Трафик: `{data_used:.2f} GB / {data_limit:.2f} GB`\n"
            f"🔄 Осталось: `{data_remaining:.2f} GB`\n"
            f"📡 IP-адрес: `{settings.SERVER_IP}`\n"
            f"🔑 Статус: `{'Активна' if subscription.is_active and not subscription.is_expired else 'Не активна'}`"
        )
    
    await message.answer(text, parse_mode="Markdown")

# Admin commands
@dp.message(Command("admin"))
async def cmd_admin(message: Message):
    """Handle /admin command."""
    user_id = message.from_user.id
    
    if user_id not in settings.ADMIN_IDS:
        await message.answer("❌ У вас нет прав администратора.")
        return
    
    # Create admin keyboard
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="👥 Пользователи", callback_data="admin_users")],
        [InlineKeyboardButton(text="📊 Статистика", callback_data="admin_stats")],
        [InlineKeyboardButton(text="⚙️ Настройки сервера", callback_data="admin_server")]
    ])
    
    await message.answer("👨‍💻 *Панель администратора*", reply_markup=keyboard, parse_mode="Markdown")

@dp.callback_query(F.data == "admin_stats")
async def admin_stats_callback(callback: CallbackQuery):
    """Handle admin stats callback."""
    if callback.from_user.id not in settings.ADMIN_IDS:
        await callback.answer("❌ У вас нет прав администратора.", show_alert=True)
        return
    
    # Get statistics
    stats = db.get_statistics()
    
    text = (
        "📊 *Статистика сервера*\n\n"
        f"👥 Всего пользователей: `{stats['total_users']}`\n"
        f"🟢 Активных подписок: `{stats['active_subscriptions']}`\n"
        f"🔴 Неактивных подписок: `{stats['inactive_subscriptions']}`\n"
        f"📊 Всего трафика: `{stats['total_traffic_gb']:.2f} GB`"
    )
    
    await callback.message.edit_text(text, parse_mode="Markdown")

async def check_subscriptions():
    """Check user subscriptions and deactivate expired ones."""
    logger.info("Running subscription check...")
    
    try:
        async with async_session_maker() as session:
            # Get all active subscriptions
            result = await session.execute(
                select(Subscription, User)
                .join(User, Subscription.user_id == User.id)
                .where(Subscription.is_active == True)
            )
            
            for subscription, user in result.all():
                try:
                    is_subscribed = await check_subscription(user.telegram_id, settings.CHANNEL_USERNAME)
                    
                    if not is_subscribed:
                        # User unsubscribed, deactivate their subscription
                        subscription.is_active = False
                        session.add(subscription)
                        
                        # Notify user
                        try:
                            await bot.send_message(
                                chat_id=user.telegram_id,
                                text=("❌ Ваша подписка была деактивирована, так как вы отписались от канала.\n"
                                      "Пожалуйста, подпишитесь снова и нажмите /start для активации подписки.")
                            )
                        except Exception as e:
                            logger.error(f"Error sending unsubscription notice to user {user.telegram_id}: {e}")
                            
                except Exception as e:
                    logger.error(f"Error processing subscription for user {user.telegram_id}: {e}")
                    
            # Commit all changes
            await session.commit()
            
            # Restart Xray to apply changes if needed
            if hasattr(server_manager, 'restart_xray'):
                try:
                    server_manager.restart_xray()
                except Exception as e:
                    logger.error(f"Error restarting Xray: {e}")
            
    except Exception as e:
        logger.error(f"Error in check_subscriptions: {e}", exc_info=True)

async def check_xray_status():
    """Check Xray service status and restart if needed."""
    try:
        status = server_manager.get_xray_status()
        logger.info(f"Xray status check result: {status}")
        
        # Check for errors first
        if status.get('error'):
            logger.error(f"Xray status check error: {status['error']}")
            return
        
        # Check if installed
        if not status.get('installed', False):
            logger.error("Xray is not installed")
            return
            
        # Check if running
        if not status.get('running', False):
            logger.warning("Xray service is not running - manual intervention may be required")
            logger.warning("To restart Xray manually, run: sudo systemctl restart xray")
        else:
            logger.info("Xray service is running normally")
            
    except Exception as e:
        logger.error(f"Error checking Xray status: {e}", exc_info=True)

# Scheduler setup
def setup_scheduler():
    """Setup background tasks."""
    # Check subscriptions every 30 minutes
    scheduler.add_job(
        check_subscriptions,
        'interval',
        minutes=30,
        id='check_subscriptions',
        replace_existing=True
    )
    
    # Check Xray status every 5 minutes
    scheduler.add_job(
        check_xray_status,
        'interval',
        minutes=5,
        id='check_xray_status',
        replace_existing=True
    )

# Startup and shutdown
async def setup_bot():
    """Setup and start the bot."""
    max_retries = 5
    retry_delay = 10
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Setting up bot... (attempt {attempt + 1}/{max_retries})")
            
            # Initialize database
            async with async_session_maker() as session:
                await init_db()
                logger.info("Database initialized")
            
            # Setup scheduler
            setup_scheduler()
            if not scheduler.running:
                scheduler.start()
                logger.info("Scheduler started")
            else:
                logger.info("Scheduler already running")
            
            # Test connection to Telegram API
            logger.info("Testing Telegram API connection...")
            try:
                # Try with longer timeout for initial connection
                me = await asyncio.wait_for(bot.get_me(), timeout=20)
                logger.info(f"Successfully connected to Telegram API. Bot: @{me.username}")
            except asyncio.TimeoutError:
                logger.error("Telegram API connection timed out")
                if attempt < max_retries - 1:
                    logger.info(f"Retrying in {retry_delay} seconds...")
                    await asyncio.sleep(retry_delay)
                    continue
                else:
                    raise
            except Exception as api_error:
                logger.error(f"Failed to connect to Telegram API: {api_error}")
                logger.error(f"Error type: {type(api_error).__name__}")
                if attempt < max_retries - 1:
                    logger.info(f"Retrying in {retry_delay} seconds...")
                    await asyncio.sleep(retry_delay)
                    continue
                else:
                    raise
            
            # Handlers are already registered via decorators
            # No need to include additional routers
            
            # Start the bot
            logger.info("Starting bot polling...")
            await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
            break
            
        except Exception as e:
            logger.error(f"Error setting up bot (attempt {attempt + 1}): {e}", exc_info=True)
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_delay} seconds...")
                await asyncio.sleep(retry_delay)
            else:
                logger.error("Max retries reached. Bot startup failed.")
                raise

if __name__ == "__main__":
    asyncio.run(setup_bot())
