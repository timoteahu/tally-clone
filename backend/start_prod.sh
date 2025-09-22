#!/bin/bash
# Production server startup script
# This script uses multiple workers to prevent request blocking

echo "🏭 Starting Joy Thief API in PRODUCTION mode..."
echo "   - Multiple workers to prevent request blocking"
echo "   - High concurrency limits"
echo "   - Production optimizations"
echo ""

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo "📦 Activating virtual environment..."
    source venv/bin/activate
fi

# Load production environment variables
if [ -f "prod.env" ]; then
    export $(cat prod.env | grep -v '^#' | xargs)
fi

# Start the server with multiple workers
python3 run_server.py 