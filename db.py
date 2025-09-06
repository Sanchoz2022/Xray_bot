import logging
from typing import Optional, List, Dict, Any, AsyncGenerator
from datetime import datetime, timedelta
from sqlalchemy import select, update, delete, func, Column, Integer, String, DateTime, Boolean, ForeignKey, Text, BigInteger
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import sessionmaker, selectinload, declarative_base, relationship, Session
from sqlalchemy.pool import NullPool

from config import settings

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# SQLAlchemy setup
Base = declarative_base()

# Database models
class User(Base):
    __tablename__ = 'users'
    
    id = Column(Integer, primary_key=True, index=True)
    telegram_id = Column(BigInteger, unique=True, index=True, nullable=False)
    username = Column(String(255), nullable=True)
    full_name = Column(String(255), nullable=True)
    is_admin = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    keys = relationship("UserKey", back_populates="user", cascade="all, delete-orphan")
    subscription = relationship("Subscription", back_populates="user", uselist=False, cascade="all, delete-orphan")
    
    def __repr__(self):
        return f"<User {self.telegram_id} ({self.username or self.full_name})>"

class UserKey(Base):
    __tablename__ = 'user_keys'
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    uuid = Column(String(36), unique=True, index=True, nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)
    data_limit_bytes = Column(BigInteger, default=1073741824)  # 1GB default
    used_bytes = Column(BigInteger, default=0)
    
    # Relationships
    user = relationship("User", back_populates="keys")
    
    @property
    def data_remaining(self) -> int:
        return max(0, self.data_limit_bytes - self.used_bytes)
    
    @property
    def is_expired(self) -> bool:
        return self.expires_at and datetime.now() > self.expires_at
    
    @property
    def has_data(self) -> bool:
        return self.data_remaining > 0

class Subscription(Base):
    __tablename__ = 'subscriptions'
    
    user_id = Column(Integer, ForeignKey('users.id', ondelete='CASCADE'), primary_key=True)
    is_active = Column(Boolean, default=False)
    last_check = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    user = relationship("User", back_populates="subscription")

# Database URL
DATABASE_URL = settings.DATABASE_URL if hasattr(settings, 'DATABASE_URL') else "sqlite+aiosqlite:///xray_bot.db"

# Create async engine
engine = create_async_engine(
    DATABASE_URL,
    echo=True,
    future=True,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20
)

# Create async session factory
async_session_maker = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False
)

# Dependency to get DB session
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependency for getting async DB session"""
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception as e:
            await session.rollback()
            logger.error(f"Database error: {e}")
            raise
        finally:
            await session.close()

# Initialize database
async def init_db():
    """Initialize database tables"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

# User operations
async def get_user(session: AsyncSession, telegram_id: int) -> Optional[User]:
    """Get user by Telegram ID"""
    result = await session.execute(
        select(User).where(User.telegram_id == telegram_id)
    )
    return result.scalar_one_or_none()

async def create_user(
    session: AsyncSession,
    telegram_id: int,
    username: Optional[str] = None,
    full_name: Optional[str] = None,
    is_admin: bool = False
) -> User:
    """Create new user"""
    user = User(
        telegram_id=telegram_id,
        username=username,
        full_name=full_name,
        is_admin=is_admin
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user

async def get_or_create_user(
    session: AsyncSession,
    telegram_id: int,
    username: Optional[str] = None,
    full_name: Optional[str] = None
) -> User:
    """Get existing user or create new one"""
    user = await get_user(session, telegram_id)
    if user is None:
        user = await create_user(session, telegram_id, username, full_name)
    return user

# Key operations
async def create_key(
    session: AsyncSession,
    user_id: int,
    uuid_str: str,
    days_valid: int = 30,
    data_limit_gb: int = 1
) -> UserKey:
    """Create new user key"""
    key = UserKey(
        user_id=user_id,
        uuid=uuid_str,
        expires_at=datetime.now() + timedelta(days=days_valid),
        data_limit_bytes=data_limit_gb * 1024 * 1024 * 1024
    )
    session.add(key)
    await session.commit()
    await session.refresh(key)
    return key

async def get_active_key(session: AsyncSession, user_id: int) -> Optional[UserKey]:
    """Get user's active key"""
    result = await session.execute(
        select(UserKey)
        .where(UserKey.user_id == user_id)
        .where(UserKey.is_active == True)
        .order_by(UserKey.created_at.desc())
    )
    return result.scalars().first()

# Subscription operations
async def update_subscription_status(
    session: AsyncSession,
    user_id: int,
    is_active: bool
) -> None:
    """Update user's subscription status"""
    await session.execute(
        update(Subscription)
        .where(Subscription.user_id == user_id)
        .values(is_active=is_active, last_check=func.now())
    )
    await session.commit()

# Create a global database instance for backward compatibility
    
    # Relationships
    user = relationship("User", back_populates="keys")

# The Subscription model is already defined above
# Remove this duplicate definition

# Create tables
async def create_tables():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

# Database operations
class Database:
    def __init__(self):
        self.SessionLocal = SessionLocal
    
    def get_db(self) -> Session:
        """Get a database session."""
        db = self.SessionLocal()
        try:
            return db
        except Exception as e:
            logger.error(f"Error creating database session: {e}")
            db.rollback()
            raise
    
    def add_user(
        self, 
        user_id: int, 
        username: str = None, 
        first_name: str = None, 
        last_name: str = None,
        is_admin: bool = False
    ) -> Optional[Dict[str, Any]]:
        """Add a new user or update existing user."""
        db = self.get_db()
        try:
            user = db.query(User).filter(User.user_id == user_id).first()
            if user:
                # Update existing user
                if username is not None:
                    user.username = username
                if first_name is not None:
                    user.first_name = first_name
                if last_name is not None:
                    user.last_name = last_name
                if is_admin:
                    user.is_admin = True
            else:
                # Create new user
                user = User(
                    user_id=user_id,
                    username=username,
                    first_name=first_name,
                    last_name=last_name,
                    is_admin=is_admin
                )
                db.add(user)
            
            db.commit()
            db.refresh(user)
            
            # Return user data as dict
            return {
                'user_id': user.user_id,
                'username': user.username,
                'first_name': user.first_name,
                'last_name': user.last_name,
                'join_date': user.join_date,
                'is_admin': user.is_admin
            }
        except Exception as e:
            db.rollback()
            logger.error(f"Error adding/updating user {user_id}: {e}")
            return None
        finally:
            db.close()
    
    def get_user(self, user_id: int) -> Optional[Dict[str, Any]]:
        """Get a user by ID."""
        db = self.get_db()
        try:
            user = db.query(User).filter(User.user_id == user_id).first()
            if user:
                return {
                    'user_id': user.user_id,
                    'username': user.username,
                    'first_name': user.first_name,
                    'last_name': user.last_name,
                    'join_date': user.join_date,
                    'is_admin': user.is_admin
                }
            return None
        except Exception as e:
            logger.error(f"Error getting user {user_id}: {e}")
            return None
        finally:
            db.close()
    
    def generate_key(
        self, 
        user_id: int, 
        days_valid: int = 30, 
        data_limit_gb: int = 1
    ) -> Optional[Dict[str, Any]]:
        """Generate a new Xray key for the user."""
        db = self.get_db()
        try:
            # Deactivate any existing active keys
            db.query(UserKey).filter(
                UserKey.user_id == user_id,
                UserKey.is_active == True
            ).update({UserKey.is_active: False})
            
            # Create new key
            key = UserKey(
                user_id=user_id,
                uuid=str(uuid.uuid4()),
                is_active=True,
                expires_at=datetime.utcnow() + timedelta(days=days_valid) if days_valid > 0 else None,
                data_limit_bytes=data_limit_gb * 1024 * 1024 * 1024,
                used_bytes=0
            )
            
            db.add(key)
            db.commit()
            db.refresh(key)
            
            return {
                'id': key.id,
                'user_id': key.user_id,
                'uuid': key.uuid,
                'is_active': key.is_active,
                'created_at': key.created_at,
                'expires_at': key.expires_at,
                'data_limit_bytes': key.data_limit_bytes,
                'used_bytes': key.used_bytes
            }
        except Exception as e:
            db.rollback()
            logger.error(f"Error generating key for user {user_id}: {e}")
            return None
        finally:
            db.close()
    
    def get_active_key(self, user_id: int) -> Optional[Dict[str, Any]]:
        """Get the active key for a user."""
        db = self.get_db()
        try:
            key = db.query(UserKey).filter(
                UserKey.user_id == user_id,
                UserKey.is_active == True
            ).first()
            
            if key:
                return {
                    'id': key.id,
                    'user_id': key.user_id,
                    'uuid': key.uuid,
                    'is_active': key.is_active,
                    'created_at': key.created_at,
                    'expires_at': key.expires_at,
                    'data_limit_bytes': key.data_limit_bytes,
                    'used_bytes': key.used_bytes
                }
            return None
        except Exception as e:
            logger.error(f"Error getting active key for user {user_id}: {e}")
            return None
        finally:
            db.close()
    
    def revoke_key(self, key_id: int) -> bool:
        """Revoke a key by ID."""
        db = self.get_db()
        try:
            result = db.query(UserKey).filter(UserKey.id == key_id).update(
                {UserKey.is_active: False}
            )
            db.commit()
            return result > 0
        except Exception as e:
            db.rollback()
            logger.error(f"Error revoking key {key_id}: {e}")
            return False
        finally:
            db.close()
    
    def update_subscription_status(self, user_id: int, is_active: bool) -> bool:
        """Update a user's subscription status."""
        db = self.get_db()
        try:
            # Check if user exists
            user = db.query(User).filter(User.user_id == user_id).first()
            if not user:
                logger.warning(f"User {user_id} not found when updating subscription")
                return False
                
            # Update or create subscription
            if user.subscription:
                user.subscription.is_active = is_active
                user.subscription.last_check = datetime.utcnow()
            else:
                subscription = Subscription(
                    is_active=is_active,
                    last_check=datetime.utcnow()
                )
                user.subscription = subscription
            
            db.commit()
            return True
        except Exception as e:
            db.rollback()
            logger.error(f"Error updating subscription for user {user_id}: {e}")
            return False
        finally:
            db.close()
    
    def check_subscription(self, user_id: int) -> bool:
        """Check if a user has an active subscription."""
        db = self.get_db()
        try:
            user = db.query(User).filter(User.user_id == user_id).first()
            if user and user.subscription:
                return user.subscription.is_active
            return False
        except Exception as e:
            logger.error(f"Error checking subscription for user {user_id}: {e}")
            return False
        finally:
            db.close()
    
    def get_active_users(self) -> List[Dict[str, Any]]:
        """Get all users with active subscriptions."""
        db = self.get_db()
        try:
            users = db.query(User).join(Subscription).filter(
                Subscription.is_active == True
            ).all()
            
            return [
                {
                    'user_id': user.user_id,
                    'username': user.username,
                    'first_name': user.first_name,
                    'last_name': user.last_name,
                    'is_admin': user.is_admin,
                    'join_date': user.join_date
                }
                for user in users
            ]
        except Exception as e:
            logger.error(f"Error getting active users: {e}")
            return []
        finally:
            db.close()

    def update_user_traffic(self, user_id: int, used_bytes: int) -> bool:
        """Update user's traffic usage."""
        db = self.get_db()
        try:
            key = db.query(UserKey).filter(
                UserKey.user_id == user_id,
                UserKey.is_active == True
            ).first()
            
            if key:
                key.used_bytes = used_bytes
                db.commit()
                return True
            return False
        except Exception as e:
            db.rollback()
            logger.error(f"Error updating traffic for user {user_id}: {e}")
            return False
        finally:
            db.close()
            
    def get_user_key_info(self, user_id: int) -> Optional[Dict[str, Any]]:
        """Get user's key information including traffic usage."""
        db = self.get_db()
        try:
            key = db.query(UserKey).filter(
                UserKey.user_id == user_id,
                UserKey.is_active == True
            ).first()
            
            if not key:
                return None
                
            user = db.query(User).filter(User.user_id == user_id).first()
            if not user:
                return None
                
            return {
                'user_id': user.user_id,
                'username': user.username,
                'uuid': key.uuid,
                'expires_at': key.expires_at,
                'data_limit': key.data_limit_bytes,
                'used_bytes': key.used_bytes,
                'is_active': key.is_active
            }
        except Exception as e:
            logger.error(f"Error getting user key info for user {user_id}: {e}")
            return None
        finally:
            db.close()

# Database setup
DATABASE_URL = "sqlite+aiosqlite:///xray_bot.db"

# Create async engine
engine = create_async_engine(
    DATABASE_URL,
    echo=True,
    future=True
)

# Create async session factory
async_session_maker = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False
)

# Create scoped session for legacy code
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine,
    class_=AsyncSession
)

# Dependency to get DB session
async def get_db() -> AsyncSession:
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

# Initialize database
async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

# Create a global database instance for backward compatibility
class Database:
    async def execute(self, query, **kwargs):
        async with SessionLocal() as session:
            try:
                result = await session.execute(query, **kwargs)
                await session.commit()
                return result
            except Exception as e:
                await session.rollback()
                raise e
            
    async def add(self, instance):
        async with SessionLocal() as session:
            try:
                session.add(instance)
                await session.commit()
                await session.refresh(instance)
                return instance
            except Exception as e:
                await session.rollback()
                raise e
                
    async def close(self):
        await engine.dispose()

# Initialize database instance
db = Database()

# Session factory for synchronous operations (for compatibility with bot.py)
def get_db_session():
    """
    Create a synchronous database session for legacy code compatibility.
    Note: This is for backward compatibility. New code should use async sessions.
    """
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    
    # Create synchronous engine from async URL
    sync_url = settings.DATABASE_URL.replace('sqlite+aiosqlite://', 'sqlite:///')
    sync_engine = create_engine(sync_url, echo=settings.SQLALCHEMY_ECHO)
    SyncSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=sync_engine)
    
    return SyncSessionLocal()
