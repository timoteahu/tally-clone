#!/bin/bash
# Development server startup script
# This script addresses the request blocking issue by using proper concurrency settings

echo "🚀 Starting Joy Thief API in DEVELOPMENT mode..."
echo "   - This configuration prevents request blocking"
echo "   - Hot reload enabled for development"
echo "   - Increased concurrency limits"
echo ""

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    echo "📦 Activating virtual environment..."
    source venv/bin/activate
fi

# Load development environment variables
if [ -f "dev.env" ]; then
    export $(cat dev.env | grep -v '^#' | xargs)
fi

# Start the server with the improved configuration
python3 run_server.py 