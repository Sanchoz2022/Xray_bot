import os
import json
from pathlib import Path
from typing import List, Optional
from dotenv import load_dotenv
from pydantic import Field, validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Load environment variables from .env file
load_dotenv()

class Settings(BaseSettings):
    # Bot configuration
    BOT_TOKEN: str = os.getenv('BOT_TOKEN', '')
    
    # Parse ADMIN_IDS directly from environment
    @property
    def ADMIN_IDS(self) -> List[int]:
        admin_ids_str = os.getenv('ADMIN_IDS', '')
        if not admin_ids_str:
            return []
        
        # Handle comma-separated values
        try:
            return [int(id.strip()) for id in admin_ids_str.split(',') if id.strip().isdigit()]
        except Exception:
            return []
        
    CHANNEL_USERNAME: str = os.getenv('CHANNEL_USERNAME', '')
    
    # Server configuration
    SERVER_IP: str = os.getenv('SERVER_IP', '')
    SERVER_DOMAIN: str = os.getenv('SERVER_DOMAIN', '')
    
    # Xray configuration
    XRAY_CONFIG_DIR: str = '/usr/local/etc/xray'
    XRAY_CONFIG_FILE: str = f'{XRAY_CONFIG_DIR}/config.json'
    XRAY_SERVICE: str = 'xray'
    XRAY_VERSION: str = '1.8.4'  # Latest stable version
    XRAY_API_HOST: str = '127.0.0.1'
    XRAY_API_PORT: int = 50051
    XRAY_API_TAG: str = 'api'
    
    # Xray Reality settings
    XRAY_REALITY_PRIVKEY: Optional[str] = os.getenv('XRAY_REALITY_PRIVKEY', '')
    XRAY_REALITY_PUBKEY: Optional[str] = os.getenv('XRAY_REALITY_PUBKEY', '')
    
    # Parse XRAY_REALITY_SHORT_IDS directly from environment
    @property
    def XRAY_REALITY_SHORT_IDS(self) -> List[str]:
        short_ids_str = os.getenv('XRAY_REALITY_SHORT_IDS', '00000000')
        if not short_ids_str:
            return ['00000000']
        
        # Handle single value or comma-separated values
        try:
            if ',' in short_ids_str:
                return [id.strip() for id in short_ids_str.split(',') if id.strip()]
            else:
                return [short_ids_str.strip()]
        except Exception:
            return ['00000000']
    
    XRAY_REALITY_DEST: str = os.getenv('XRAY_REALITY_DEST', 'www.google.com:443')
    XRAY_REALITY_XVER: int = 0
    
    # Database configuration
    DATABASE_URL: str = Field(
        default='sqlite+aiosqlite:///./xray_bot.db',
        alias='DATABASE_URL',
        env='DATABASE_URL',
        description='Database connection URL. For SQLite use: sqlite+aiosqlite:///./your_db.db',
    )
    
    # SQLAlchemy settings
    SQLALCHEMY_ECHO: bool = False
    SQLALCHEMY_POOL_SIZE: int = 5
    SQLALCHEMY_MAX_OVERFLOW: int = 10
    
    # gRPC API Settings
    GRPC_API_HOST: str = os.getenv('GRPC_API_HOST', '127.0.0.1')
    GRPC_API_PORT: int = int(os.getenv('GRPC_API_PORT', '50051'))
    
    # Subscription Settings
    DEFAULT_SUBSCRIPTION_DAYS: int = int(os.getenv('DEFAULT_SUBSCRIPTION_DAYS', '30'))
    DEFAULT_DATA_LIMIT_GB: int = int(os.getenv('DEFAULT_DATA_LIMIT_GB', '100'))
    
    # Paths
    BASE_DIR: Path = Path(__file__).parent
    LOG_DIR: Path = BASE_DIR / 'logs'
    LOG_FILE: Path = LOG_DIR / 'bot.log'
    
    model_config = SettingsConfigDict(
        env_file='.env',
        env_file_encoding='utf-8',
        # Allow extra fields to prevent validation errors
        extra='allow',
        # Disable automatic JSON parsing for environment variables
        env_parse_none_str='',
        case_sensitive=False
    )

# Create settings instance
settings = Settings()

# Ensure log directory exists
os.makedirs(settings.LOG_DIR, exist_ok=True)
XRAY_REALITY_XVER = 0

# Generate Reality keys if not set
if not settings.XRAY_REALITY_PRIVKEY or not settings.XRAY_REALITY_PUBKEY:
    import subprocess
    try:
        result = subprocess.run(
            ['xray', 'x25519'],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'Private key' in line:
                    private_key = line.split(':')[1].strip()
                    settings.XRAY_REALITY_PRIVKEY = private_key
                elif 'Public key' in line:
                    public_key = line.split(':')[1].strip()
                    settings.XRAY_REALITY_PUBKEY = public_key
            
            # Save to .env file if not exists
            env_file = Path(__file__).parent / '.env'
            if not env_file.exists():
                with open(env_file, 'w') as f:
                    f.write(f'XRAY_REALITY_PRIVKEY={settings.XRAY_REALITY_PRIVKEY}\n')
                    f.write(f'XRAY_REALITY_PUBKEY={settings.XRAY_REALITY_PUBKEY}\n')
    except Exception as e:
        print(f"Warning: Could not generate Xray Reality keys: {e}")
