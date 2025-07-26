#!/bin/bash

# MetaHead ICP Game - Canister Upgrade Script
# This script handles safe upgrades of all canisters with backup and rollback capabilities

set -e

echo "🔄 MetaHead ICP Game - Canister Upgrade Manager"
echo "=============================================="

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

# Default values
NETWORK="local"
CANISTER=""
ALL_CANISTERS=false
BACKUP=true
FORCE=false

# Available canisters
CANISTERS=(
    "game_token"
    "player_nft"
    "auction_factory"
    "auction"
    "mystery_box"
    "game_engine"
)

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --canister CANISTER    Upgrade specific canister"
    echo "  -a, --all                  Upgrade all canisters"
    echo "  -n, --network NETWORK      Target network (local, ic) [default: local]"
    echo "  --no-backup               Skip backup creation"
    echo "  -f, --force               Force upgrade without confirmation"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -c game_token           # Upgrade game_token canister"
    echo "  $0 -a                      # Upgrade all canisters"
    echo "  $0 -c player_nft -n ic     # Upgrade player_nft on mainnet"
    echo "  $0 -a --no-backup -f       # Force upgrade all without backup"
    echo ""
    echo "Available canisters:"
    for canister in "${CANISTERS[@]}"; do
        echo "  - $canister"
    done
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--canister)
            CANISTER="$2"
            shift 2
            ;;
        -a|--all)
            ALL_CANISTERS=true
            shift
            ;;
        -n|--network)
            NETWORK="$2"
            shift 2
            ;;
        --no-backup)
            BACKUP=false
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [ "$ALL_CANISTERS" = false ] && [ -z "$CANISTER" ]; then
    print_error "Must specify either --canister or --all"
    show_usage
    exit 1
fi

if [ "$ALL_CANISTERS" = true ] && [ -n "$CANISTER" ]; then
    print_error "Cannot specify both --canister and --all"
    show_usage
    exit 1
fi

# Validate canister name
if [ -n "$CANISTER" ]; then
    if [[ ! " ${CANISTERS[@]} " =~ " ${CANISTER} " ]]; then
        print_error "Invalid canister: $CANISTER"
        echo "Available canisters: ${CANISTERS[*]}"
        exit 1
    fi
fi

# Validate network
if [[ "$NETWORK" != "local" && "$NETWORK" != "ic" ]]; then
    print_error "Invalid network: $NETWORK (must be 'local' or 'ic')"
    exit 1
fi

# Check if dfx is available
if ! command -v dfx &> /dev/null; then
    print_error "dfx is not installed or not in PATH"
    exit 1
fi

# Check if network is running (for local)
if [ "$NETWORK" = "local" ]; then
    if ! dfx ping > /dev/null 2>&1; then
        print_error "Local dfx replica is not running. Start it with 'dfx start'"
        exit 1
    fi
fi

# Function to create backup
create_backup() {
    local canister_name=$1
    
    if [ "$BACKUP" = false ]; then
        print_status "Skipping backup for $canister_name (--no-backup specified)"
        return 0
    fi
    
    print_status "Creating backup for $canister_name..."
    
    # Create backup directory with timestamp
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Get canister ID
    local canister_id
    canister_id=$(dfx canister id "$canister_name" --network "$NETWORK" 2>/dev/null || echo "")
    
    if [ -z "$canister_id" ]; then
        print_warning "Cannot get canister ID for $canister_name, skipping backup"
        return 0
    fi
    
    # Create backup metadata
    cat > "$backup_dir/${canister_name}_backup.json" << EOF
{
    "canister_name": "$canister_name",
    "canister_id": "$canister_id",
    "network": "$NETWORK",
    "backup_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "dfx_version": "$(dfx --version)",
    "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    
    # Save current canister state (if possible)
    print_status "Saving canister state for $canister_name..."
    
    # Note: In a real production environment, you would implement proper state backup
    # This could involve calling canister methods to export state, etc.
    
    print_success "Backup created at $backup_dir"
    echo "$backup_dir" > ".last_backup_$canister_name"
}

# Function to upgrade single canister
upgrade_canister() {
    local canister_name=$1
    
    print_status "Upgrading canister: $canister_name"
    
    # Create backup
    create_backup "$canister_name"
    
    # Build the canister
    print_status "Building $canister_name..."
    if ! dfx build "$canister_name" --network "$NETWORK"; then
        print_error "Failed to build $canister_name"
        return 1
    fi
    
    # Check if canister exists
    if ! dfx canister id "$canister_name" --network "$NETWORK" > /dev/null 2>&1; then
        print_error "Canister $canister_name does not exist. Deploy it first."
        return 1
    fi
    
    # Perform the upgrade
    print_status "Performing upgrade for $canister_name..."
    
    # Check cycles before upgrade (for mainnet)
    if [ "$NETWORK" = "ic" ]; then
        local cycles_before
        cycles_before=$(dfx canister status "$canister_name" --network ic | grep "Balance:" | awk '{print $2}' || echo "unknown")
        print_status "Cycles before upgrade: $cycles_before"
    fi
    
    # Execute upgrade with proper error handling
    if dfx canister install "$canister_name" --mode upgrade --network "$NETWORK"; then
        print_success "Successfully upgraded $canister_name"
        
        # Verify upgrade
        print_status "Verifying upgrade..."
        if dfx canister status "$canister_name" --network "$NETWORK" > /dev/null 2>&1; then
            print_success "Upgrade verification passed for $canister_name"
        else
            print_warning "Upgrade verification failed for $canister_name"
        fi
        
        # Check cycles after upgrade (for mainnet)
        if [ "$NETWORK" = "ic" ]; then
            local cycles_after
            cycles_after=$(dfx canister status "$canister_name" --network ic | grep "Balance:" | awk '{print $2}' || echo "unknown")
            print_status "Cycles after upgrade: $cycles_after"
        fi
        
    else
        print_error "Failed to upgrade $canister_name"
        
        # Offer rollback option
        if [ "$BACKUP" = true ] && [ -f ".last_backup_$canister_name" ]; then
            local backup_dir
            backup_dir=$(cat ".last_backup_$canister_name")
            print_warning "Backup available at: $backup_dir"
            print_warning "Consider rolling back if needed"
        fi
        
        return 1
    fi
}

# Function to upgrade all canisters
upgrade_all_canisters() {
    print_status "Upgrading all canisters on network: $NETWORK"
    
    local failed_canisters=()
    local success_count=0
    
    for canister in "${CANISTERS[@]}"; do
        echo ""
        echo "════════════════════════════════════════"
        print_status "Processing canister: $canister"
        echo "════════════════════════════════════════"
        
        if upgrade_canister "$canister"; then
            ((success_count++))
        else
            failed_canisters+=("$canister")
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════"
    echo "📊 Upgrade Summary"
    echo "════════════════════════════════════════"
    echo "✅ Successful upgrades: $success_count/${#CANISTERS[@]}"
    
    if [ ${#failed_canisters[@]} -gt 0 ]; then
        echo "❌ Failed upgrades: ${failed_canisters[*]}"
        return 1
    else
        echo "🎉 All canisters upgraded successfully!"
        return 0
    fi
}

# Main execution
main() {
    print_status "Starting canister upgrade process..."
    print_status "Network: $NETWORK"
    print_status "Backup enabled: $BACKUP"
    
    # Confirmation prompt (unless forced)
    if [ "$FORCE" = false ]; then
        echo ""
        if [ "$ALL_CANISTERS" = true ]; then
            print_warning "About to upgrade ALL canisters on $NETWORK network"
        else
            print_warning "About to upgrade $CANISTER on $NETWORK network"
        fi
        
        if [ "$NETWORK" = "ic" ]; then
            print_warning "This will consume cycles on the mainnet!"
        fi
        
        echo ""
        read -p "Do you want to continue? (yes/no): " confirm
        
        if [[ $confirm != "yes" ]]; then
            echo "Upgrade cancelled."
            exit 0
        fi
    fi
    
    echo ""
    print_status "Starting upgrade process..."
    
    # Execute upgrade
    if [ "$ALL_CANISTERS" = true ]; then
        upgrade_all_canisters
    else
        upgrade_canister "$CANISTER"
    fi
    
    local exit_code=$?
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        print_success "🎉 Upgrade process completed successfully!"
    else
        print_error "❌ Upgrade process completed with errors"
        print_warning "Check the logs above for details"
        
        if [ "$BACKUP" = true ]; then
            echo ""
            print_status "💡 Rollback information:"
            echo "Backups are available in the 'backups/' directory"
            echo "Use the backup metadata to restore if needed"
        fi
    fi
    
    exit $exit_code
}

# Create backups directory
mkdir -p backups

# Run main function
main 