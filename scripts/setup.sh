#!/bin/bash

# MetaHead ICP Game - Initial Setup Script
# This script sets up the development environment and installs dependencies

set -e

echo "🎮 MetaHead ICP Game - Initial Setup"
echo "===================================="

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

# Check if running on supported OS
case "$(uname -s)" in
    Linux*)     MACHINE=Linux;;
    Darwin*)    MACHINE=Mac;;
    *)          MACHINE="UNKNOWN"
esac

print_status "Detected OS: $MACHINE"

if [ "$MACHINE" = "UNKNOWN" ]; then
    print_error "Unsupported operating system"
    exit 1
fi

# Check prerequisites
print_status "Checking prerequisites..."

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    print_error "curl is required but not installed."
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    print_warning "Node.js not found. Installing Node.js..."
    if [ "$MACHINE" = "Linux" ]; then
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    elif [ "$MACHINE" = "Mac" ]; then
        # Install using Homebrew if available, otherwise provide instructions
        if command -v brew &> /dev/null; then
            brew install node
        else
            print_error "Please install Node.js manually from https://nodejs.org/"
            exit 1
        fi
    fi
fi

NODE_VERSION=$(node --version)
print_success "Node.js version: $NODE_VERSION"

# Check if Rust is installed
if ! command -v rustc &> /dev/null; then
    print_warning "Rust not found. Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
fi

RUST_VERSION=$(rustc --version)
print_success "Rust version: $RUST_VERSION"

# Install wasm32 target for Rust
print_status "Installing wasm32-unknown-unknown target..."
rustup target add wasm32-unknown-unknown

# Check if DFX is installed
if ! command -v dfx &> /dev/null; then
    print_warning "DFX not found. Installing DFX..."
    sh -ci "$(curl -fsSL https://sdk.dfinity.org/install.sh)"
    
    # Add dfx to PATH for current session
    export PATH="$HOME/.local/share/dfx/bin:$PATH"
fi

DFX_VERSION=$(dfx --version)
print_success "DFX version: $DFX_VERSION"

# Create necessary directories
print_status "Creating project directories..."
mkdir -p .dfx
mkdir -p target
mkdir -p node_modules

# Install npm dependencies (if package.json exists)
if [ -f "package.json" ]; then
    print_status "Installing npm dependencies..."
    npm install
    print_success "npm dependencies installed"
fi

# Build all canisters to check everything is working
print_status "Building all canisters to verify setup..."
dfx build

print_success "All canisters built successfully!"

# Generate Candid bindings
print_status "Generating Candid bindings..."
dfx generate

# Create .env file for local development
print_status "Creating local environment configuration..."
cat > .env << EOF
# MetaHead ICP Game - Local Development Configuration
# Generated on: $(date)

# Network Configuration
DFX_NETWORK=local
DFX_PORT=4943

# Canister IDs (will be populated after first deployment)
GAME_TOKEN_CANISTER_ID=
PLAYER_NFT_CANISTER_ID=
AUCTION_FACTORY_CANISTER_ID=
AUCTION_CANISTER_ID=
MYSTERY_BOX_CANISTER_ID=
GAME_ENGINE_CANISTER_ID=

# Development Settings
NODE_ENV=development
DEBUG=true

# Frontend Configuration (when ready)
REACT_APP_IC_HOST=http://localhost:4943
REACT_APP_IC_AGENT_HOST=http://localhost:4943
EOF

print_success ".env file created"

# Setup git hooks (if git is initialized)
if [ -d ".git" ]; then
    print_status "Setting up git hooks..."
    
    # Pre-commit hook to run tests and formatting
    cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Pre-commit hook for MetaHead ICP Game

echo "Running pre-commit checks..."

# Check Rust formatting
if ! cargo fmt --check; then
    echo "Error: Code is not properly formatted. Run 'cargo fmt' to fix."
    exit 1
fi

# Run Rust clippy for linting
if ! cargo clippy -- -D warnings; then
    echo "Error: Clippy found issues. Please fix them before committing."
    exit 1
fi

# Build all canisters
if ! dfx build; then
    echo "Error: Build failed. Please fix compilation errors."
    exit 1
fi

echo "Pre-commit checks passed!"
EOF
    
    chmod +x .git/hooks/pre-commit
    print_success "Git hooks configured"
fi

# Create development scripts shortcuts
print_status "Creating development shortcuts..."

# Create quick start script
cat > quick-start.sh << 'EOF'
#!/bin/bash
# Quick start script for MetaHead ICP development

echo "🚀 Starting MetaHead ICP development environment..."

# Start local replica in background
dfx start --background --clean

# Deploy all canisters
dfx deploy

# Show canister URLs
echo ""
echo "🎮 MetaHead ICP Game is ready!"
echo "Candid UI: http://localhost:4943"
echo ""
echo "Canister IDs:"
dfx canister id --all

echo ""
echo "Use 'dfx stop' to stop the local replica when done."
EOF

chmod +x quick-start.sh

print_success "Development shortcuts created"

# Final setup summary
echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "✅ Prerequisites installed:"
echo "   - Node.js: $NODE_VERSION"
echo "   - Rust: $RUST_VERSION" 
echo "   - DFX: $DFX_VERSION"
echo ""
echo "✅ Project configured:"
echo "   - All dependencies installed"
echo "   - Canisters built successfully"
echo "   - Development environment ready"
echo ""
echo "🚀 Next Steps:"
echo "   1. Run './quick-start.sh' to start development"
echo "   2. Or manually start with 'dfx start --background'"
echo "   3. Deploy canisters with 'dfx deploy'"
echo ""
echo "📚 Available Scripts:"
echo "   - ./quick-start.sh - Start development environment"
echo "   - ./deploy.sh - Deploy to local network"
echo "   - ./deploy-production.sh - Deploy to IC mainnet"
echo "   - ./scripts/upgrade.sh - Upgrade canisters"
echo ""
echo "🎮 Happy coding!" 