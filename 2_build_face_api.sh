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
    local url=$1
    if [[ $url =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?$ ]]; then
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
    print_status "  - http://localhost:8000"
    print_status "  - http://YOUR_SERVER_IP:8000"
    print_status "  - http://compreface:8000"
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

# Step 3: Verify CompreFace is accessible
print_status "Step 3: Verifying CompreFace is accessible..."
VERIFICATION_URL="${COMPRE_FACE_URL}/api/v1/verification/verify"
if curl -s -f "$VERIFICATION_URL" > /dev/null 2>&1; then
    print_success "CompreFace is accessible at $COMPRE_FACE_URL"
else
    print_warning "Cannot reach CompreFace at $COMPRE_FACE_URL"
    print_status "Make sure CompreFace is running and accessible"
    print_status "You can check with: curl $VERIFICATION_URL"
    read -p "Continue anyway? (y/N): " continue_anyway
    if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
        exit 1
    fi
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

# Step 9: Test the API
print_status "Step 9: Testing Face API..."
if curl -s -f http://localhost:${PORT}/ > /dev/null 2>&1; then
    print_success "Face API is running and accessible"
    echo ""
    print_success "🎉 Face API setup completed successfully!"
    echo ""
    echo "📋 Face API Information:"
    echo "   URL: http://localhost:${PORT}"
    echo "   Health Check: http://localhost:${PORT}/"
    echo "   API Endpoint: http://localhost:${PORT}/compare-faces"
    echo ""
    echo "🔍 To check Face API logs:"
    echo "   docker logs ${CONTAINER_NAME}"
    echo "   docker logs -f ${CONTAINER_NAME}  # Follow logs"
    echo ""
    echo "🛑 To stop Face API:"
    echo "   docker stop ${CONTAINER_NAME}"
    echo "   docker rm ${CONTAINER_NAME}"
    echo ""
    echo "🔄 To restart Face API:"
    echo "   docker restart ${CONTAINER_NAME}"
    echo ""
    echo "📖 Test the API:"
    echo "   curl http://localhost:${PORT}/"
    echo ""
    echo "📝 Example API call:"
    echo "   curl -X POST http://localhost:${PORT}/compare-faces \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"image1\": \"base64_image_1\", \"image2\": \"base64_image_2\"}'"
else
    print_error "Face API is not responding"
    print_status "Checking logs..."
    docker logs ${CONTAINER_NAME}
    exit 1
fi
