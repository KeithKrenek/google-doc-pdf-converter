#!/bin/bash

# Quick Fix for Dockerfile Build Error
# This script fixes the libgdk-pixbuf package issue

set -e

echo "🔧 Fixing Dockerfile build error..."

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo "❌ Dockerfile not found in current directory"
    exit 1
fi

# Backup original Dockerfile
cp Dockerfile Dockerfile.backup
echo "📋 Backed up original Dockerfile to Dockerfile.backup"

# Fix the problematic package name
echo "🔧 Fixing package names in Dockerfile..."

# Create the fixed Dockerfile
cat > Dockerfile << 'EOF'
# Use Python 3.11 slim image for better performance
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Install system dependencies for WeasyPrint and image processing
RUN apt-get update && apt-get install -y \
    curl \
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    libfontconfig1 \
    libcairo2 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    shared-mime-info \
    fonts-dejavu-core \
    fonts-liberation \
    fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*

# Set work directory
WORKDIR /app

# Copy requirements first for better Docker layer caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .
COPY .env* ./

# Create directories for temporary files
RUN mkdir -p /tmp/pdf_temp

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app /tmp/pdf_temp
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Command to run the application
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 --max-requests 1000 --max-requests-jitter 100 main:app
EOF

echo "✅ Fixed Dockerfile created"

# Also create a more robust alternative
cat > Dockerfile.robust << 'EOF'
# Use Python 3.11 slim image for better performance
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Update package list and install curl
RUN apt-get update && apt-get install -y curl

# Install WeasyPrint system dependencies with better error handling
RUN apt-get install -y \
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    libfontconfig1 \
    libcairo2 \
    libffi-dev \
    shared-mime-info \
    && apt-get clean

# Try multiple package names for gdk-pixbuf (different Debian versions)
RUN (apt-get install -y libgdk-pixbuf-2.0-0 || \
     apt-get install -y libgdk-pixbuf2.0-0 || \
     apt-get install -y libgdk-pixbuf-xlib-2.0-0 || \
     echo "Warning: gdk-pixbuf not found, trying to continue...")

# Install fonts
RUN apt-get install -y \
    fonts-dejavu-core \
    fonts-liberation \
    fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*

# Set work directory
WORKDIR /app

# Copy and install requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Test WeasyPrint installation
RUN python -c "import weasyprint; print('WeasyPrint OK')"

# Copy application code
COPY main.py .
COPY .env* ./

# Create directories and user
RUN mkdir -p /tmp/pdf_temp
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app /tmp/pdf_temp
USER appuser

# Expose port and set health check
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run application
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF

echo "✅ Created Dockerfile.robust as backup option"

echo ""
echo "🚀 Now retry your build with:"
echo "gcloud builds submit --config cloudbuild.yaml"
echo ""
echo "Or if issues persist, try the robust version:"
echo "mv Dockerfile.robust Dockerfile"
echo "gcloud builds submit --config cloudbuild.yaml"
echo ""
echo "📋 Files created:"
echo "- Dockerfile (fixed)"
echo "- Dockerfile.robust (alternative)"
echo "- Dockerfile.backup (your original)"