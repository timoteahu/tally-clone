#!/bin/bash
# Lightweight server startup (1 worker with hot reload)
echo "🔧 Starting Joy Thief API in LIGHTWEIGHT mode..."
echo "   - 1 worker with hot reload"
echo "   - For active development"

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Start with 1 worker and hot reload
DEVELOPMENT=true WORKERS=1 python3 run_server.py 