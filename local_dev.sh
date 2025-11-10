#!/bin/bash

#####################################################################
# Local Development Helper Script
# Quickly set up and run the converter locally for testing
#####################################################################

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Google Doc to PDF - Local Development${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}\n"

# Check for Python
if ! command -v python3 &> /dev/null; then
    print_warning "Python 3 is required but not found"
    exit 1
fi

print_success "Python 3 found: $(python3 --version)"

# Check for virtual environment
if [ ! -d "venv" ]; then
    print_status "Creating virtual environment..."
    python3 -m venv venv
    print_success "Virtual environment created"
fi

# Activate virtual environment
print_status "Activating virtual environment..."
source venv/bin/activate

# Install dependencies
print_status "Installing dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt
print_success "Dependencies installed"

# Check for .env file
if [ ! -f ".env" ]; then
    print_warning ".env file not found"
    print_status "Creating .env from .env.example..."
    cp .env.example .env
    print_warning "Please edit .env with your configuration before running"
    exit 0
fi

# Check for service account key
if [ ! -f "service-account-key.json" ]; then
    print_warning "Service account key file not found: service-account-key.json"
    print_status "Please place your service account key file in the project root"
    exit 0
fi

# Load environment variables
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Set local development variables
export GOOGLE_APPLICATION_CREDENTIALS="./service-account-key.json"
export PORT="${PORT:-8080}"

print_success "Environment configured"
echo ""
echo "Configuration:"
echo "  PORT: $PORT"
echo "  BUCKET: ${BUCKET_NAME:-Not set}"
echo "  PROJECT: ${PROJECT_ID:-Not set}"
echo ""

# Run the application
print_status "Starting development server..."
echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"

python3 main.py
