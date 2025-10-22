#!/bin/bash

# Face API Build Script
# This script builds the Face API Docker image with CompreFace credentials
# Requires: CompreFace API key and URL (both must be provided)

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root (allow for Vast AI and cloud environments)
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root (detected Vast AI or cloud environment)"
    print_status "This is acceptable for cloud GPU instances"
else
    print_status "Running as regular user"
fi

echo "🚀 Starting Face API Build..."

# Vast AI / Cloud Environment Notes:
# - Running as root is acceptable for cloud GPU instances
# - Docker commands work directly without sudo
# - GPU access is typically pre-configured
#
# Requirements:
# - CompreFace API key (from CompreFace UI -> Application Management)
# - CompreFace base URL (e.g., http://localhost:8000)

# Configuration
CONTAINER_NAME="face-api"
IMAGE_NAME="face-api"
PORT="5000"

# Step 1: Check if we're in the correct directory and Docker is available
if [ ! -f "api/face_compare.py" ]; then
    print_error "Please run this script from the face-verification root directory"
    print_status "Current directory: $(pwd)"
    print_status "Expected structure: face-verification/api/face_compare.py"
    exit 1
fi

# Function to validate URL format (up to port number)
validate_url() {
    url=$1
    # Remove trailing slash if present for validation
    url_no_slash="${url%/}"
    echo "$url_no_slash" | grep -Eq '^https?://([a-zA-Z0-9.-]+|([0-9]{1,3}\.){3}[0-9]{1,3})(:[0-9]+)?$'
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Step 2: Get CompreFace credentials from user
print_status "Step 2: Getting CompreFace credentials..."

# Get API key
if [ -z "$COMPRE_FACE_API_KEY" ]; then
    echo ""
    print_warning "Please enter your CompreFace API key:"
    print_status "You can find this in CompreFace UI -> Application Management"
    read -p "API Key: " COMPRE_FACE_API_KEY
    
    if [ -z "$COMPRE_FACE_API_KEY" ]; then
        print_error "API key is required!"
        exit 1
    fi
fi

# Get CompreFace URL (required)
if [ -z "$COMPRE_FACE_URL" ]; then
    echo ""
    print_warning "Please enter your CompreFace base URL:"
    print_status "Examples:"
    print_status "  - http://YOUR_SERVER_PUBLICIP:8000"
    read -p "CompreFace URL: " COMPRE_FACE_URL
    
    if [ -z "$COMPRE_FACE_URL" ]; then
        print_error "CompreFace URL is required!"
        print_status "Please provide a valid CompreFace base URL"
        exit 1
    fi
fi

# Validate URL format
if ! validate_url "$COMPRE_FACE_URL"; then
    print_error "Invalid URL format: $COMPRE_FACE_URL"
    print_status "Please provide a valid URL (e.g., http://localhost:8000)"
    exit 1
fi


# Step 4: Clean up existing container and image
print_status "Step 4: Cleaning up existing containers and images..."
if docker ps -a --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_warning "Stopping and removing existing ${CONTAINER_NAME} container..."
    docker stop ${CONTAINER_NAME} 2>/dev/null || true
    docker rm ${CONTAINER_NAME} 2>/dev/null || true
fi

if docker images --format 'table {{.Repository}}' | grep -q "^${IMAGE_NAME}$"; then
    print_warning "Removing existing ${IMAGE_NAME} image..."
    docker rmi ${IMAGE_NAME} 2>/dev/null || true
fi

# Step 5: Build Docker image
print_status "Step 5: Building Face API Docker image..."
docker build \
    --build-arg COMPRE_FACE_API_KEY="$COMPRE_FACE_API_KEY" \
    --build-arg COMPRE_FACE_URL="$VERIFICATION_URL" \
    -t ${IMAGE_NAME} ./api

if [ $? -eq 0 ]; then
    print_success "Face API Docker image built successfully"
else
    print_error "Failed to build Docker image"
    exit 1
fi

# Step 6: Create environment file
print_status "Step 6: Creating environment file..."
cat > .env << EOF
# Face API Configuration
COMPRE_FACE_API_KEY=$COMPRE_FACE_API_KEY
COMPRE_FACE_URL=$VERIFICATION_URL
EOF
print_success "Environment file created"

# Step 7: Run Face API container
print_status "Step 7: Starting Face API container..."
docker run -d \
    --name ${CONTAINER_NAME} \
    --restart unless-stopped \
    -p ${PORT}:5000 \
    -e COMPRE_FACE_API_KEY="$COMPRE_FACE_API_KEY" \
    -e COMPRE_FACE_URL="$VERIFICATION_URL" \
    ${IMAGE_NAME}

if [ $? -eq 0 ]; then
    print_success "Face API container started successfully"
else
    print_error "Failed to start Face API container"
    exit 1
fi

# Step 8: Wait for service to be ready
print_status "Step 8: Waiting for Face API to be ready..."
sleep 10
