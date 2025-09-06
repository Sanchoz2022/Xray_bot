import os
import json
from pathlib import Path
from typing import List, Optional
from dotenv import load_dotenv
from pydantic import Field, validator
from pydantic_settings import BaseSettings

# Load environment variables from .env file
load_dotenv()

class Settings(BaseSettings):
    # Bot configuration
    BOT_TOKEN: str = os.getenv('BOT_TOKEN', '')
    ADMIN_IDS: List[int] = Field(
        default_factory=list,
        description="Comma-separated list of admin user IDs",
        json_schema_extra={"env": "ADMIN_IDS"}
    )
    
    @validator('ADMIN_IDS', pre=True)
    def parse_admin_ids(cls, v):
        if isinstance(v, str):
            return [int(id.strip()) for id in v.split(',') if id.strip().isdigit()]
        return v or []
        
    @validator('XRAY_REALITY_SHORT_IDS', pre=True)
    def parse_short_ids(cls, v):
        if v is None:
            return []
        if isinstance(v, str):
            # If it's already a JSON array string, parse it
            if v.startswith('[') and v.endswith(']'):
                try:
                    return json.loads(v)
                except json.JSONDecodeError:
                    pass
            # Otherwise treat as comma-separated string
            v = v.strip('"\'')
            if not v:  # If string is empty after stripping
                return []
            return [id.strip() for id in v.split(',') if id.strip()]
        return v or []
        
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
    XRAY_REALITY_PRIVKEY: str = os.getenv('XRAY_REALITY_PRIVKEY', '')
    XRAY_REALITY_PUBKEY: str = os.getenv('XRAY_REALITY_PUBKEY', '')
    XRAY_REALITY_SHORT_IDS: List[str] = Field(
        default_factory=list,
        description="Comma-separated list of short IDs for Reality protocol. Can be a JSON array or comma-separated string.",
        json_schema_extra={"env": "XRAY_REALITY_SHORT_IDS"}
    )
    
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
    
    class Config:
        env_file = '.env'
        env_file_encoding = 'utf-8'

# Create settings instance
settings = Settings()

# Ensure log directory exists
os.makedirs(settings.LOG_DIR, exist_ok=True)
XRAY_REALITY_XVER = 0

# Generate Reality keys if not set
if not XRAY_REALITY_PRIVKEY or not XRAY_REALITY_PUBKEY:
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
                    XRAY_REALITY_PRIVKEY = line.split(':')[1].strip()
                elif 'Public key' in line:
                    XRAY_REALITY_PUBKEY = line.split(':')[1].strip()
            
            # Save to .env file if not exists
            env_file = Path(__file__).parent / '.env'
            if not env_file.exists():
                with open(env_file, 'w') as f:
                    f.write(f'XRAY_REALITY_PRIVKEY={XRAY_REALITY_PRIVKEY}\n')
                    f.write(f'XRAY_REALITY_PUBKEY={XRAY_REALITY_PUBKEY}\n')
    except Exception as e:
        print(f"Warning: Could not generate Xray Reality keys: {e}")

# Database configuration
DB_URL = os.getenv('DATABASE_URL', f'sqlite:///{Path(__file__).parent}/xray_bot.db')

# Paths
BASE_DIR = Path(__file__).parent
LOG_DIR = BASE_DIR / 'logs'
LOG_FILE = LOG_DIR / 'bot.log'
XRAY_LOGFILE = '/var/log/xray/access.log'

# Create necessary directories
os.makedirs(LOG_DIR, exist_ok=True)
