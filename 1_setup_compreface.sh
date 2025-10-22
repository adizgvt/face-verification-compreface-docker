#!/bin/bash

# CompreFace Setup Script
# This script sets up and runs CompreFace with GPU support

set -e  # Exit on any error

echo "🚀 Starting CompreFace Setup..."

# Vast AI / Cloud Environment Notes:
# - Running as root is acceptable for cloud GPU instances
# - Docker commands work directly without sudo
# - GPU access is typically pre-configured
# - nvidia-docker2 installation may be needed

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
    print_status "Note: Some commands may need to be run without 'sudo' prefix"
else
    print_status "Running as regular user"
fi

# Step 1: Clone CompreFace repository
print_status "Step 1: Cloning CompreFace repository..."
if [ ! -d "CompreFace" ]; then
    git clone https://github.com/exadel-inc/CompreFace.git
    print_success "CompreFace repository cloned successfully"
else
    print_warning "CompreFace directory already exists, skipping clone"
fi

# Step 2: Navigate to GPU build directory
print_status "Step 2: Navigating to GPU build directory..."
cd CompreFace/custom-builds/SubCenter-ArcFace-r100-gpu
print_success "Changed to CompreFace GPU build directory"

# Step 3: Install nvidia-docker2
print_status "Step 3: Installing nvidia-docker2..."
if ! dpkg -l | grep -q nvidia-docker2; then
    if [ "$EUID" -eq 0 ]; then
        apt update
        apt install -y nvidia-docker2
    else
        sudo apt update
        sudo apt install -y nvidia-docker2
    fi
    print_success "nvidia-docker2 installed successfully"
else
    print_warning "nvidia-docker2 already installed"
fi

# Step 4: Restart Docker service
print_status "Step 4: Restarting Docker service..."
if [ "$EUID" -eq 0 ]; then
    systemctl restart docker
else
    sudo systemctl restart docker
fi
print_success "Docker service restarted"

# Step 5: Setup environment file
print_status "Step 5: Setting up environment configuration..."
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        print_success "Environment file created from example"
    else
        # Create basic .env file
        cat > .env << EOF
# Database settings
postgres_username=postgres
postgres_password=compreface_password_123
postgres_db=compreface

# CompreFace versions
POSTGRES_VERSION=latest
ADMIN_VERSION=latest
API_VERSION=latest
FE_VERSION=latest
CORE_VERSION=latest

# GPU settings
uwsgi_processes=2
uwsgi_threads=1
max_detect_size=640

# Other settings
save_images_to_db=false
max_file_size=5
max_request_size=5
connection_timeout=10000
read_timeout=60000
EOF
        print_success "Basic environment file created"
    fi
else
    print_warning "Environment file already exists"
fi

# Step 6: Start CompreFace services
print_status "Step 6: Starting CompreFace services..."
docker compose up -d
print_success "CompreFace services started"

# Step 7: Wait for services to be ready
print_status "Step 7: Waiting for services to be ready..."
sleep 30

# Step 8: Check CompreFace Core (GPU service)
print_status "Step 8: Checking CompreFace Core GPU service..."
if docker compose ps | grep -q "compreface-core.*Up"; then
    print_success "CompreFace Core is running"
    
    # Run nvidia-smi inside compreface-core container
    print_status "Running nvidia-smi inside CompreFace Core container..."
    docker compose exec compreface-core nvidia-smi || {
        print_warning "nvidia-smi failed inside container, but service is running"
    }
else
    print_error "CompreFace Core is not running properly"
    print_status "Checking logs..."
    docker compose logs compreface-core
    exit 1
fi

# Step 9: Check all services status
print_status "Step 9: Checking all services status..."
docker compose ps

# Step 10: Get CompreFace URL and instructions
print_success "🎉 CompreFace setup completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Open CompreFace UI in your browser:"
echo "   http://$(hostname -I | awk '{print $1}'):8000"
echo "   or http://localhost:8000"
echo ""
echo "2. Create an API key:"
echo "   - Go to 'Application Management'"
echo "   - Create a new application"
echo "   - Copy the API key"
echo ""
echo "3. Note the CompreFace URL:"
echo "   http://$(hostname -I | awk '{print $1}'):8000/api/v1/verification/verify"
echo ""
echo "4. Run the second script to build Face API:"
echo "   cd /path/to/face_api"
echo "   ./2_build_face_api.sh"
echo ""
echo "🔍 To check CompreFace logs:"
echo "   docker compose logs -f"
echo ""
echo "🛑 To stop CompreFace:"
echo "   docker compose down"
