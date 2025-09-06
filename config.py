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
        if v is None or v == '':
            return []
            
        # If it's already a list, return as is
        if isinstance(v, list):
            return [int(x) if isinstance(x, str) and x.isdigit() else x for x in v if x]
            
        if isinstance(v, str):
            # Remove any surrounding quotes and whitespace
            v = v.strip().strip('"\'')
            
            # If empty string, return empty list
            if not v:
                return []
                
            # If it's a JSON array string, try to parse it
            if v.startswith('[') and v.endswith(']'):
                try:
                    import json
                    result = json.loads(v)
                    if isinstance(result, list):
                        return [int(x) for x in result if str(x).isdigit()]
                except json.JSONDecodeError:
                    # If JSON parsing fails, try to extract values manually
                    try:
                        # Remove brackets and split by comma
                        clean_v = v.strip('[]').strip()
                        if clean_v:
                            # Split by comma and clean each value
                            values = [val.strip().strip('"\'') for val in clean_v.split(',')]
                            return [int(val) for val in values if val.isdigit()]
                        else:
                            return []
                    except Exception:
                        return []
                        
            # Handle comma-separated values
            try:
                return [int(id.strip()) for id in v.split(',') if id.strip().isdigit()]
            except Exception:
                return []
                
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
    XRAY_REALITY_PRIVKEY: str = os.getenv('XRAY_REALITY_PRIVKEY', '')
    XRAY_REALITY_PUBKEY: str = os.getenv('XRAY_REALITY_PUBKEY', '')
    XRAY_REALITY_SHORT_IDS: List[str] = Field(
        default_factory=lambda: ['00000000'],
        description="Comma-separated list of short IDs for Reality protocol. Can be a JSON array or comma-separated string.",
        json_schema_extra={"env": "XRAY_REALITY_SHORT_IDS"}
    )
    
    @validator('XRAY_REALITY_SHORT_IDS', pre=True)
    def parse_short_ids(cls, v):
        if v is None or v == '':
            return ['00000000']  # Default short ID if none provided
            
        # If it's already a list, return as is
        if isinstance(v, list):
            return v if v else ['00000000']
            
        if isinstance(v, str):
            # Remove any surrounding quotes and whitespace
            v = v.strip().strip('"\'')
            
            # If empty string, return default
            if not v:
                return ['00000000']
                
            # If it's a JSON array string, try to parse it
            if v.startswith('[') and v.endswith(']'):
                try:
                    result = json.loads(v)
                    if isinstance(result, list):
                        return result if result else ['00000000']
                except json.JSONDecodeError as e:
                    # If JSON parsing fails, try to extract values manually
                    try:
                        # Remove brackets and split by comma
                        clean_v = v.strip('[]').strip()
                        if clean_v:
                            # Split by comma and clean each value
                            values = [val.strip().strip('"\'') for val in clean_v.split(',')]
                            values = [val for val in values if val]  # Remove empty values
                            return values if values else ['00000000']
                        else:
                            return ['00000000']
                    except Exception:
                        # If all else fails, return default
                        return ['00000000']
                    
            # If it's a single value, wrap it in a list
            if not any(c in v for c in '[],'):
                return [v] if v.strip() else ['00000000']
                
            # Handle comma-separated values
            try:
                values = [id.strip().strip('"\'') for id in v.split(',') if id.strip()]
                return values if values else ['00000000']
            except Exception:
                return ['00000000']
            
        # If we get here, return default
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
    
    class Config:
        env_file = '.env'
        env_file_encoding = 'utf-8'

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
