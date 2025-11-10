# Use Python 3.11 slim image for optimal performance
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Install system dependencies for image processing and fonts
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    libfontconfig1 \
    libcairo2 \
    libgdk-pixbuf-2.0-0 \
    libjpeg62-turbo \
    libpng16-16 \
    fonts-dejavu-core \
    fonts-liberation \
    fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better Docker layer caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Copy assets directory (if it exists)
COPY assets/ ./assets/ 2>/dev/null || true

# Create directories for temporary files
RUN mkdir -p /tmp/pdf_temp && \
    chmod 777 /tmp/pdf_temp

# Create non-root user for security
RUN groupadd -r appuser && \
    useradd -r -g appuser appuser && \
    chown -R appuser:appuser /app /tmp/pdf_temp

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the application with gunicorn
CMD exec gunicorn \
    --bind :$PORT \
    --workers 1 \
    --threads 8 \
    --timeout 300 \
    --max-requests 1000 \
    --max-requests-jitter 100 \
    --access-logfile - \
    --error-logfile - \
    --log-level info \
    main:app
