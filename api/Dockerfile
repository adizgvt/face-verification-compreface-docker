# Use Python 3.11 slim image as base
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies required for ImageMagick
RUN apt-get update && apt-get install -y \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY face_compare.py .
COPY gunicorn.conf.py .

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

# Expose port 5000
EXPOSE 5000

# Accept API key and URL as build arguments
ARG COMPRE_FACE_API_KEY
ARG COMPRE_FACE_URL
ENV COMPRE_FACE_API_KEY=${COMPRE_FACE_API_KEY}
ENV COMPRE_FACE_URL=${COMPRE_FACE_URL}

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/ || exit 1

# Run the application with Gunicorn
CMD ["gunicorn", "--config", "gunicorn.conf.py", "face_compare:app"]
