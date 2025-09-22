#!/usr/bin/env python3
"""
Server startup script with multiple workers to prevent request blocking.
This script addresses the issue where one request blocks others on localhost.
"""

import uvicorn
import os
import sys
from pathlib import Path

# Add the app directory to Python path
sys.path.append(str(Path(__file__).parent / "app"))

def main():
    # Server configuration
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", 8000))
    workers = int(os.getenv("WORKERS", 4))
    development = os.getenv("DEVELOPMENT", "true").lower() == "true"
    
    print(f"🚀 Starting Joy Thief API server...")
    print(f"   Host: {host}")
    print(f"   Port: {port}")
    print(f"   Workers: {workers}")
    print(f"   Development mode: {development}")
    print(f"   Multiple workers will prevent request blocking!")
    
    if development:
        # Development mode with hot reload (single worker)
        print("\n📝 Development mode: Hot reload enabled, single worker")
        uvicorn.run(
            "main:app",
            host=host,
            port=port,
            reload=True,
            workers=1,  # Hot reload requires single worker
            app_dir="app",
            limit_concurrency=100,
            timeout_keep_alive=5
        )
    else:
        # Production mode with multiple workers
        print(f"\n🏭 Production mode: {workers} workers for concurrent request handling")
        uvicorn.run(
            "main:app",
            host=host,
            port=port,
            workers=workers,
            reload=False,
            app_dir="app",
            limit_concurrency=1000,
            timeout_keep_alive=30,
            # Use worker processes to prevent blocking
            worker_class="uvicorn.workers.UvicornWorker"
        )

if __name__ == "__main__":
    main() 