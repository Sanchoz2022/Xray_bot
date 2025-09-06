#!/usr/bin/env python3
"""Initialize the database and apply migrations."""
import asyncio
from db import init_db, engine, Base

async def main():
    print("Initializing database...")
    await init_db()
    print("Database initialized successfully!")

if __name__ == "__main__":
    asyncio.run(main())
