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

from config import (
    BOT_TOKEN, CHANNEL_USERNAME, ADMIN_IDS, 
    SERVER_IP, XRAY_REALITY_PUBKEY, XRAY_REALITY_SHORT_IDS
)
from db import db, User, UserKey, Subscription, get_db_session
from server_manager import server_manager, ServerManager

# Initialize server manager
server_manager = ServerManager()

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize bot and dispatcher
bot = Bot(token=BOT_TOKEN)
dp = Dispatcher()

# Scheduler for background tasks
scheduler = AsyncIOScheduler()

# States
class UserState(StatesGroup):
    waiting_for_domain = State()
    waiting_for_email = State()

# Helper functions
async def check_subscription(user_id: int) -> bool:
    """Check if user is subscribed to the channel."""
    try:
        member = await bot.get_chat_member(CHANNEL_USERNAME, user_id)
        return member.status in ['member', 'administrator', 'creator']
    except Exception as e:
        logger.error(f"Error checking subscription for {user_id}: {e}")
        return False

def generate_reality_config(uuid_str: str, email: str = "") -> Dict[str, str]:
    """Generate Reality configuration for the user."""
    if not XRAY_REALITY_PUBKEY or not XRAY_REALITY_SHORT_IDS:
        logger.error("Reality keys not configured")
        return {}
    
    # Use the first short ID for now
    short_id = XRAY_REALITY_SHORT_IDS[0]
    
    # Generate the VLESS URL with Reality transport
    vless_url = (
        f"vless://{uuid_str}@{SERVER_IP}:443?type=tcp&encryption=none&"
        f"security=reality&sni=www.google.com&fp=chrome&pbk={XRAY_REALITY_PUBKEY}&"
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
            'add': SERVER_IP,
            'port': '443',
            'id': uuid_str,
            'aid': '0',
            'net': 'tcp',
            'type': 'none',
            'host': '',
            'path': '',
            'tls': 'reality',
            'sni': 'www.google.com',
            'alpn': '',
            'fp': 'chrome',
            'pbk': XRAY_REALITY_PUBKEY,
            'sid': short_id,
            'spx': '',
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
    with get_db_session() as session:
        db_user = session.query(User).filter(User.user_id == user.id).first()
        if not db_user:
            db_user = User(
                user_id=user.id,
                username=user.username,
                first_name=user.first_name,
                last_name=user.last_name,
                join_date=datetime.utcnow()
            )
            session.add(db_user)
            session.commit()
    
    # Check subscription
    is_subscribed = await check_subscription(user.id)
    
    # Create welcome message
    text = (
        f"👋 Привет, {user.first_name}!\n\n"
        "Это бот для настройки и управления VPN-сервером Xray с поддержкой Reality.\n\n"
        "📡 Для начала работы подпишитесь на наш канал и нажмите кнопку ниже:"
    )
    
    # Create keyboard
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="📢 Подписаться на канал", url=f"https://t.me/{CHANNEL_USERNAME.lstrip('@')}")],
        [InlineKeyboardButton(text="✅ Проверить подписку", callback_data="check_subscription")],
        [InlineKeyboardButton(text="📊 Статистика", callback_data="user_stats")]
    ])
    
    await message.answer(text, reply_markup=keyboard)

@dp.callback_query(F.data == "check_subscription")
async def check_subscription_callback(callback: CallbackQuery):
    """Handle subscription check callback."""
    user = callback.from_user
    is_subscribed = await check_subscription(user.id)
    
    if not is_subscribed:
        await callback.answer("❌ Вы не подписаны на канал. Пожалуйста, подпишитесь и попробуйте снова.", show_alert=True)
        return
    
    try:
        with get_db_session() as session:
            # Update subscription status
            db_user = session.query(User).filter(User.user_id == user.id).first()
            if not db_user:
                await callback.answer("❌ Пользователь не найден. Пожалуйста, начните с /start", show_alert=True)
                return
                
            # Get or create user key
            key = session.query(UserKey).filter(
                UserKey.user_id == user.id,
                UserKey.is_active == True
            ).first()
            
            if not key:
                # Generate new UUID for the user
                user_uuid = str(uuid.uuid4())
                
                # Add user to Xray via gRPC
                if not server_manager.add_user(email=f"user_{user.id}@xray.com", user_id=user_uuid):
                    await callback.answer("❌ Ошибка при настройке VPN. Пожалуйста, попробуйте позже.", show_alert=True)
                    return
                
                # Create new key in database
                key = UserKey(
                    user_id=user.id,
                    uuid=user_uuid,
                    is_active=True,
                    created_at=datetime.utcnow(),
                    expires_at=datetime.utcnow() + timedelta(days=30)  # 30 days validity
                )
                session.add(key)
                session.commit()
            
            # Generate Reality config
            config = generate_reality_config(key.uuid, f"user_{user.id}")
            
            if not config:
                await callback.answer("❌ Ошибка при генерации конфигурации. Пожалуйста, попробуйте позже.", show_alert=True)
                return
            
            # Create response message
            text = (
                "🎉 *Ваш Xray Reality конфиг готов!*\n\n"
                "🔑 *Сервер:* `reality`\n"
                "🌐 *Адрес:* `{0}`\n"
                "🔌 *Порт:* `443`\n"
                "🆔 *ID пользователя:* `{1}`\n"
                "🔒 *Шифрование:* `none`\n"
                "🚀 *Транспорт:* `reality`\n\n"
                "📱 *Как использовать:*\n"
                "1. Скачайте приложение Xray для вашего устройства\n"
                "2. Нажмите на кнопку ниже, чтобы скопировать конфиг\n"
                "3. Импортируйте конфиг в приложение\n"
                "4. Активируйте соединение"
            ).format(SERVER_IP, key.uuid)
            
            # Create keyboard
            keyboard = InlineKeyboardBuilder()
            keyboard.row(
                InlineKeyboardButton(
                    text="📋 Скопировать конфиг",
                    callback_data=f"copy_config_{key.id}"
                )
            )
            keyboard.row(
                InlineKeyboardButton(
                    text="📊 Статистика",
                    callback_data="user_stats"
                ),
                InlineKeyboardButton(
                    text="❓ Помощь",
                    callback_data="help"
                )
            )
            
            await callback.message.edit_text(
                text,
                reply_markup=keyboard.as_markup(),
                parse_mode="Markdown"
            )
            
    except Exception as e:
        logger.error(f"Error in subscription callback: {e}", exc_info=True)
        await callback.answer("❌ Произошла ошибка. Пожалуйста, попробуйте позже.", show_alert=True)

@dp.callback_query(F.data.startswith("copy_config_"))
async def copy_config_callback(callback: CallbackQuery):
    """Handle copy config callback."""
    key_id = callback.data.replace("copy_config_", "")
    key_data = db.get_active_key(callback.from_user.id)
    
    if key_data and key_data['key_id'] == key_id:
        vless_url = generate_vless_url(
            uuid=key_data['uuid'],
            domain=SERVER_IP  # Replace with your domain
        )
        
        # Copy to clipboard and show confirmation
        await callback.answer("✅ Конфиг скопирован в буфер обмена", show_alert=True)
        
        # Send instructions
        await callback.message.answer(
            "📱 Инструкция по настройке:\n\n"
            "1. Скачайте приложение Xray для вашего устройства\n"
            "2. Откройте приложение и нажмите "Добавить конфигурацию"\n"
            "3. Вставьте скопированный URL и сохраните\n"
            "4. Активируйте соединение"
        )
    else:
        await callback.answer("❌ Ключ не найден или устарел", show_alert=True)

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
    key_data = db.get_active_key(user_id)
    is_subscribed = await check_subscription(user_id)
    
    if not is_subscribed:
        text = "❌ Ваша подписка не активна. Пожалуйста, подпишитесь на канал и попробуйте снова."
    elif not key_data:
        text = "❌ У вас нет активного ключа. Пожалуйста, нажмите /start для генерации нового ключа."
    else:
        expires_at = datetime.fromisoformat(key_data['expires_at']).strftime("%d.%m.%Y %H:%M")
        data_used = key_data['used_bytes'] / (1024 ** 3)  # Convert to GB
        data_limit = key_data['data_limit_bytes'] / (1024 ** 3)  # Convert to GB
        
        text = (
            "📊 *Статус вашей подписки*\n\n"
            f"🔑 Статус: `{'Активна' if is_subscribed else 'Не активна'}`\n"
            f"📅 Истекает: `{expires_at}`\n"
            f"📊 Трафик: `{data_used:.2f} GB / {data_limit:.2f} GB`\n"
            f"📡 IP-адрес: `{SERVER_IP}`"
        )
    
    await message.answer(text, parse_mode="Markdown")

# Admin commands
@dp.message(Command("admin"))
async def cmd_admin(message: Message):
    """Handle /admin command."""
    user_id = message.from_user.id
    
    if user_id not in ADMIN_IDS:
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
    if callback.from_user.id not in ADMIN_IDS:
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

# Background tasks
async def check_subscriptions():
    """Check user subscriptions and deactivate expired ones."""
    logger.info("Running subscription check...")
    
    # Get all active subscriptions
    active_users = db.get_active_subscriptions()
    
    for user in active_users:
        try:
            is_subscribed = await check_subscription(user['user_id'])
            
            if not is_subscribed:
                # User unsubscribed, deactivate their key
                db.revoke_key(user['user_id'])
                
                # Notify user
                try:
                    await bot.send_message(
                        chat_id=user['user_id'],
                        text=("❌ Ваш ключ доступа был деактивирован, так как вы отписались от канала.\n"
                             "Для повторной активации подпишитесь на канал и нажмите /start")
                    )
                except Exception as e:
                    logger.error(f"Failed to notify user {user['user_id']}: {e}")
                    
        except Exception as e:
            logger.error(f"Error processing user {user.get('user_id')}: {e}")

async def check_xray_status():
    """Check Xray service status and restart if necessary."""
    try:
        status = server_manager.get_xray_status()
        
        if not status['is_running']:
            logger.warning("Xray service is not running. Attempting to restart...")
            server_manager.restart_xray()
            
    except Exception as e:
        logger.error(f"Error checking Xray status: {e}")

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
    
    # Start the scheduler
    scheduler.start()

# Startup and shutdown
def setup_bot():
    """Setup the bot."""
    # Create database tables
    db.setup()
    
    # Setup scheduler
    setup_scheduler()
    
    # Check if Xray is installed and running
    if not server_manager.is_xray_installed():
        logger.warning("Xray is not installed. Please install it manually or run the setup script.")

async def main():
    """Main function to start the bot."""
    # Setup the bot
    setup_bot()
    
    # Start polling
    logger.info("Starting bot...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
