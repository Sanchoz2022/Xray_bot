import logging
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any, Type, TypeVar, Generic
import uuid
import json
from pathlib import Path
from sqlalchemy import create_engine, Column, Integer, String, Boolean, DateTime, ForeignKey, BigInteger, func
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship, scoped_session
from sqlalchemy.pool import StaticPool

from config import settings
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create SQLAlchemy engine and session
if settings.DB_URL.startswith('sqlite'):
    # For SQLite, we need to add check_same_thread=False
    engine = create_engine(
        settings.DB_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool
    )
else:
    engine = create_engine(settings.DB_URL)

# Create a scoped session factory
SessionLocal = scoped_session(
    sessionmaker(autocommit=False, autoflush=False, bind=engine)
)

Base = declarative_base()

# Database models
class User(Base):
    """User model representing a Telegram user."""
    __tablename__ = 'users'
    
    user_id = Column(BigInteger, primary_key=True, index=True)
    username = Column(String(255), nullable=True)
    first_name = Column(String(255), nullable=True)
    last_name = Column(String(255), nullable=True)
    join_date = Column(DateTime, default=datetime.utcnow)
    is_admin = Column(Boolean, default=False)
    
    # Relationships
    keys = relationship("UserKey", back_populates="user", cascade="all, delete-orphan")
    subscription = relationship("Subscription", back_populates="user", uselist=False, cascade="all, delete-orphan")

class UserKey(Base):
    """User key model for Xray VLESS configurations."""
    __tablename__ = 'user_keys'
    
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(BigInteger, ForeignKey('users.user_id', ondelete='CASCADE'), nullable=False)
    uuid = Column(String(36), unique=True, index=True, nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=True)
    data_limit_bytes = Column(BigInteger, default=1073741824)  # 1GB default
    used_bytes = Column(BigInteger, default=0)
    
    # Relationships
    user = relationship("User", back_populates="keys")

class Subscription(Base):
    """Subscription model for channel subscriptions."""
    __tablename__ = 'subscriptions'
    
    user_id = Column(BigInteger, ForeignKey('users.user_id', ondelete='CASCADE'), primary_key=True)
    is_active = Column(Boolean, default=False)
    last_check = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    user = relationship("User", back_populates="subscription")

# Create tables
Base.metadata.create_all(bind=engine)

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
                logger.error(f"Error getting active users: {e}")
                return []

# Create a global database instance
db = Database()
