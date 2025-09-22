#!/bin/bash
# Heavy-duty server startup (8 workers for high load)
echo "⚡ Starting Joy Thief API in HEAVY-DUTY mode..."
echo "   - 8 workers for maximum concurrent request handling"
echo "   - For load testing and high traffic"

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Start with 8 workers (no hot reload)
DEVELOPMENT=false WORKERS=8 python3 run_server.py 