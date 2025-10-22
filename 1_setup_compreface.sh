#!/bin/bash

# CompreFace Setup Script
# This script sets up CompreFace configuration and verifies the setup

set -e  # Exit on any error

echo "🚀 Starting CompreFace Setup..."

# Vast AI / Cloud Environment Notes:
# - Running as root is acceptable for cloud GPU instances
# - Docker commands work directly without sudo
# - GPU access is typically pre-configured
# - nvidia-docker2 installation may be needed
#
# Prerequisites:
# - CompreFace docker-compose.yml must exist in ./compreface/ directory
# - .env file should already exist in ./compreface/ directory

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

# Step 1: Check for existing CompreFace setup
print_status "Step 1: Checking for existing CompreFace setup..."
if [ ! -f "compreface/docker-compose.yml" ]; then
    print_error "CompreFace docker-compose.yml not found!"
    print_status "Please ensure docker-compose.yml exists in ./compreface/ directory"
    exit 1
else
    print_success "CompreFace docker-compose.yml found"
fi

# Step 2: Navigate to CompreFace directory
print_status "Step 2: Navigating to CompreFace directory..."
cd compreface
print_success "Changed to CompreFace directory"

# Step 3: Check for .env file
print_status "Step 3: Checking for .env file..."
if [ ! -f ".env" ]; then
    print_error ".env file not found in compreface directory!"
    print_status "Please ensure .env file exists in ./compreface/ directory"
    exit 1
else
    print_success ".env file found"
fi

# Step 4: Install nvidia-docker2
print_status "Step 4: Installing nvidia-docker2..."
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

# Step 5: Restart Docker service
print_status "Step 5: Restarting Docker service..."
if [ "$EUID" -eq 0 ]; then
    systemctl restart docker
else
    sudo systemctl restart docker
fi
print_success "Docker service restarted"

# Step 6: Check CompreFace services status
print_status "Step 6: Checking CompreFace services status..."
if docker compose ps | grep -q "compreface-core.*Up"; then
    print_success "CompreFace Core is running"
    
    # Run nvidia-smi inside compreface-core container
    print_status "Running nvidia-smi inside CompreFace Core container..."
    docker compose exec compreface-core nvidia-smi || {
        print_warning "nvidia-smi failed inside container, but service is running"
    }
else
    print_warning "CompreFace Core is not running"
    print_status "You may need to start CompreFace services manually:"
    print_status "  docker compose up -d"
    print_status "Checking all services status..."
fi

# Step 7: Check all services status
print_status "Step 7: Checking all services status..."
docker compose ps

# Step 8: Get CompreFace URL and instructions
print_success "🎉 CompreFace setup completed successfully!"
