#!/bin/bash

# MetaHead ICP Game - Frontend Build Script
# This script builds the Next.js frontend for ICP deployment

set -e

echo "🎨 Building Next.js Frontend for ICP..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if we're in the right directory
if [ ! -d "frontend" ]; then
    print_error "frontend/ directory not found. Run this script from the project root."
    exit 1
fi

# Navigate to frontend directory
cd frontend

# Check if package.json exists
if [ ! -f "package.json" ]; then
    print_error "package.json not found in frontend directory"
    exit 1
fi

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    print_status "Installing frontend dependencies..."
    npm install
    print_success "Dependencies installed"
fi

# Generate DFX types and declarations
print_status "Generating DFX declarations..."
cd ..
dfx generate
cd frontend

# Build the Next.js application
print_status "Building Next.js application..."
npm run build

# Check if build was successful
if [ ! -d "out" ]; then
    print_error "Build failed - 'out' directory not found"
    exit 1
fi

print_success "Frontend build completed successfully!"
print_status "Static files are ready in frontend/out/"

# Show build info
echo ""
echo "📊 Build Summary:"
echo "================"
echo "Output directory: frontend/out/"
echo "Ready for ICP deployment via dfx deploy frontend"
echo ""

cd .. 