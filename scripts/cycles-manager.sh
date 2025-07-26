#!/bin/bash

# MetaHead ICP Game - Cycles Management Script
# This script manages cycles for all canisters with monitoring and automatic distribution

set -e

echo "💰 MetaHead ICP Game - Cycles Manager"
echo "====================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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

print_cycles() {
    echo -e "${MAGENTA}[CYCLES]${NC} $1"
}

# Default values
NETWORK="ic"
ACTION=""
CANISTER=""
AMOUNT=""

# Cycles thresholds (in cycles)
CRITICAL_THRESHOLD=100000000000  # 100B cycles
WARNING_THRESHOLD=500000000000   # 500B cycles
TARGET_BALANCE=2000000000000     # 2T cycles

# Available canisters with their typical consumption patterns
declare -A CANISTER_PROFILES=(
    ["game_token"]="high"         # High usage - token transfers
    ["player_nft"]="medium"       # Medium usage - NFT operations
    ["auction_factory"]="low"     # Low usage - creates auctions
    ["auction"]="low"             # Low usage - individual auction
    ["mystery_box"]="high"        # High usage - randomness + minting
    ["game_engine"]="very_high"   # Very high usage - game logic
)

# Target cycles per canister type
declare -A TARGET_CYCLES=(
    ["very_high"]=5000000000000   # 5T cycles
    ["high"]=3000000000000        # 3T cycles
    ["medium"]=2000000000000      # 2T cycles
    ["low"]=1000000000000         # 1T cycles
)

# Function to show usage
show_usage() {
    echo "Usage: $0 ACTION [OPTIONS]"
    echo ""
    echo "Actions:"
    echo "  status                     Show cycles status for all canisters"
    echo "  monitor                    Monitor cycles and show alerts"
    echo "  distribute                 Distribute cycles to low canisters"
    echo "  top-up CANISTER AMOUNT     Top up specific canister"
    echo "  balance                    Show wallet balance"
    echo "  emergency                  Emergency cycles distribution"
    echo ""
    echo "Options:"
    echo "  -n, --network NETWORK      Target network (ic) [default: ic]"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 status                  # Show all canister cycles"
    echo "  $0 monitor                 # Monitor and show alerts"
    echo "  $0 distribute              # Auto-distribute cycles"
    echo "  $0 top-up game_engine 1000000000000  # Top up 1T cycles"
    echo "  $0 emergency               # Emergency distribution"
    echo ""
    echo "Canister Profiles:"
    for canister in "${!CANISTER_PROFILES[@]}"; do
        echo "  - $canister: ${CANISTER_PROFILES[$canister]} usage"
    done
}

# Parse command line arguments
case "${1:-}" in
    status|monitor|distribute|balance|emergency)
        ACTION="$1"
        shift
        ;;
    top-up)
        ACTION="top-up"
        CANISTER="$2"
        AMOUNT="$3"
        shift 3
        ;;
    -h|--help|"")
        show_usage
        exit 0
        ;;
    *)
        print_error "Unknown action: $1"
        show_usage
        exit 1
        ;;
esac

# Parse remaining options
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--network)
            NETWORK="$2"
            shift 2
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

# Validate network
if [[ "$NETWORK" != "ic" ]]; then
    print_error "Cycles management is only available on IC mainnet"
    exit 1
fi

# Check if dfx is available
if ! command -v dfx &> /dev/null; then
    print_error "dfx is not installed or not in PATH"
    exit 1
fi

# Function to format cycles
format_cycles() {
    local cycles=$1
    
    if [ "$cycles" = "unknown" ] || [ -z "$cycles" ]; then
        echo "unknown"
        return
    fi
    
    # Remove any non-numeric characters and get the number
    local num=$(echo "$cycles" | sed 's/[^0-9]//g')
    
    if [ -z "$num" ]; then
        echo "unknown"
        return
    fi
    
    # Convert to human readable format
    if [ "$num" -ge 1000000000000 ]; then
        echo "$(($num / 1000000000000))T"
    elif [ "$num" -ge 1000000000 ]; then
        echo "$(($num / 1000000000))B"
    elif [ "$num" -ge 1000000 ]; then
        echo "$(($num / 1000000))M"
    else
        echo "${num}"
    fi
}

# Function to get canister cycles
get_canister_cycles() {
    local canister_name=$1
    local cycles
    
    cycles=$(dfx canister status "$canister_name" --network "$NETWORK" 2>/dev/null | grep "Balance:" | awk '{print $2}' | sed 's/[^0-9]//g' || echo "0")
    
    if [ -z "$cycles" ] || [ "$cycles" = "0" ]; then
        echo "0"
    else
        echo "$cycles"
    fi
}

# Function to get wallet balance
get_wallet_balance() {
    local balance
    balance=$(dfx wallet balance --network "$NETWORK" 2>/dev/null | sed 's/[^0-9]//g' || echo "0")
    echo "$balance"
}

# Function to check canister status
check_canister_status() {
    local canister_name=$1
    local cycles
    
    cycles=$(get_canister_cycles "$canister_name")
    
    if [ "$cycles" = "0" ]; then
        echo "OFFLINE"
    elif [ "$cycles" -lt "$CRITICAL_THRESHOLD" ]; then
        echo "CRITICAL"
    elif [ "$cycles" -lt "$WARNING_THRESHOLD" ]; then
        echo "WARNING"
    else
        echo "HEALTHY"
    fi
}

# Function to show cycles status
show_status() {
    print_status "Checking cycles status for all canisters..."
    echo ""
    
    # Show wallet balance first
    local wallet_balance
    wallet_balance=$(get_wallet_balance)
    print_cycles "Wallet Balance: $(format_cycles "$wallet_balance") cycles"
    echo ""
    
    # Table header
    printf "%-20s %-12s %-15s %-10s %s\n" "CANISTER" "PROFILE" "CYCLES" "STATUS" "RECOMMENDATION"
    printf "%-20s %-12s %-15s %-10s %s\n" "--------" "-------" "------" "------" "--------------"
    
    local total_cycles=0
    local critical_count=0
    local warning_count=0
    
    for canister in "${!CANISTER_PROFILES[@]}"; do
        local cycles
        local status
        local profile
        local recommendation
        
        cycles=$(get_canister_cycles "$canister")
        status=$(check_canister_status "$canister")
        profile="${CANISTER_PROFILES[$canister]}"
        
        # Calculate recommendation
        local target_for_profile="${TARGET_CYCLES[$profile]}"
        if [ "$cycles" -lt "$target_for_profile" ]; then
            local needed=$((target_for_profile - cycles))
            recommendation="Top up $(format_cycles "$needed")"
        else
            recommendation="OK"
        fi
        
        # Status coloring
        case "$status" in
            "CRITICAL")
                status="${RED}CRITICAL${NC}"
                ((critical_count++))
                ;;
            "WARNING")
                status="${YELLOW}WARNING${NC}"
                ((warning_count++))
                ;;
            "HEALTHY")
                status="${GREEN}HEALTHY${NC}"
                ;;
            "OFFLINE")
                status="${RED}OFFLINE${NC}"
                ((critical_count++))
                ;;
        esac
        
        printf "%-20s %-12s %-15s %-19s %s\n" \
            "$canister" \
            "$profile" \
            "$(format_cycles "$cycles")" \
            "$status" \
            "$recommendation"
        
        total_cycles=$((total_cycles + cycles))
    done
    
    echo ""
    print_cycles "Total Cycles Across Canisters: $(format_cycles "$total_cycles")"
    
    if [ "$critical_count" -gt 0 ]; then
        print_error "$critical_count canister(s) in CRITICAL state!"
    fi
    
    if [ "$warning_count" -gt 0 ]; then
        print_warning "$warning_count canister(s) in WARNING state"
    fi
    
    if [ "$critical_count" -eq 0 ] && [ "$warning_count" -eq 0 ]; then
        print_success "All canisters are healthy!"
    fi
}

# Function to monitor and alert
monitor_cycles() {
    print_status "Monitoring cycles across all canisters..."
    
    local alerts=()
    local total_needed=0
    
    for canister in "${!CANISTER_PROFILES[@]}"; do
        local cycles
        local status
        local profile
        
        cycles=$(get_canister_cycles "$canister")
        status=$(check_canister_status "$canister")
        profile="${CANISTER_PROFILES[$canister]}"
        
        case "$status" in
            "CRITICAL"|"OFFLINE")
                alerts+=("🚨 CRITICAL: $canister has $(format_cycles "$cycles") cycles")
                local target="${TARGET_CYCLES[$profile]}"
                total_needed=$((total_needed + target))
                ;;
            "WARNING")
                alerts+=("⚠️  WARNING: $canister has $(format_cycles "$cycles") cycles")
                local target="${TARGET_CYCLES[$profile]}"
                local needed=$((target - cycles))
                total_needed=$((total_needed + needed))
                ;;
        esac
    done
    
    if [ ${#alerts[@]} -gt 0 ]; then
        echo ""
        print_error "ALERTS DETECTED:"
        for alert in "${alerts[@]}"; do
            echo "  $alert"
        done
        
        echo ""
        print_warning "Total cycles needed for healthy state: $(format_cycles "$total_needed")"
        
        local wallet_balance
        wallet_balance=$(get_wallet_balance)
        
        if [ "$wallet_balance" -gt "$total_needed" ]; then
            print_success "Wallet has sufficient cycles for distribution"
            echo ""
            read -p "Would you like to auto-distribute cycles now? (y/n): " auto_distribute
            if [[ $auto_distribute =~ ^[Yy]$ ]]; then
                distribute_cycles
            fi
        else
            print_error "Insufficient wallet balance! Please top up your wallet."
            echo "Required: $(format_cycles "$total_needed")"
            echo "Available: $(format_cycles "$wallet_balance")"
        fi
    else
        print_success "No alerts - all canisters are healthy!"
    fi
}

# Function to distribute cycles
distribute_cycles() {
    print_status "Distributing cycles to canisters based on their profiles..."
    
    local wallet_balance
    wallet_balance=$(get_wallet_balance)
    
    if [ "$wallet_balance" -lt 1000000000000 ]; then
        print_error "Insufficient wallet balance for distribution"
        print_error "Current balance: $(format_cycles "$wallet_balance")"
        exit 1
    fi
    
    local distributions=0
    
    for canister in "${!CANISTER_PROFILES[@]}"; do
        local cycles
        local status
        local profile
        
        cycles=$(get_canister_cycles "$canister")
        status=$(check_canister_status "$canister")
        profile="${CANISTER_PROFILES[$canister]}"
        
        local target="${TARGET_CYCLES[$profile]}"
        
        if [ "$cycles" -lt "$target" ]; then
            local needed=$((target - cycles))
            
            print_status "Topping up $canister with $(format_cycles "$needed") cycles..."
            
            if dfx canister deposit-cycles "$needed" "$canister" --network "$NETWORK"; then
                print_success "Successfully topped up $canister"
                ((distributions++))
            else
                print_error "Failed to top up $canister"
            fi
        fi
    done
    
    if [ "$distributions" -gt 0 ]; then
        print_success "Distributed cycles to $distributions canister(s)"
    else
        print_status "No distributions needed - all canisters are sufficiently funded"
    fi
}

# Function to top up specific canister
top_up_canister() {
    local canister_name=$1
    local amount=$2
    
    if [ -z "$canister_name" ] || [ -z "$amount" ]; then
        print_error "Usage: $0 top-up CANISTER AMOUNT"
        exit 1
    fi
    
    # Validate canister name
    if [[ ! " ${!CANISTER_PROFILES[@]} " =~ " ${canister_name} " ]]; then
        print_error "Invalid canister: $canister_name"
        echo "Available canisters: ${!CANISTER_PROFILES[@]}"
        exit 1
    fi
    
    # Validate amount is numeric
    if ! [[ "$amount" =~ ^[0-9]+$ ]]; then
        print_error "Amount must be a number (in cycles)"
        exit 1
    fi
    
    print_status "Topping up $canister_name with $(format_cycles "$amount") cycles..."
    
    # Check wallet balance
    local wallet_balance
    wallet_balance=$(get_wallet_balance)
    
    if [ "$wallet_balance" -lt "$amount" ]; then
        print_error "Insufficient wallet balance!"
        print_error "Required: $(format_cycles "$amount")"
        print_error "Available: $(format_cycles "$wallet_balance")"
        exit 1
    fi
    
    # Perform top-up
    if dfx canister deposit-cycles "$amount" "$canister_name" --network "$NETWORK"; then
        print_success "Successfully topped up $canister_name"
        
        # Show new balance
        local new_cycles
        new_cycles=$(get_canister_cycles "$canister_name")
        print_cycles "New balance: $(format_cycles "$new_cycles") cycles"
    else
        print_error "Failed to top up $canister_name"
        exit 1
    fi
}

# Function for emergency distribution
emergency_distribution() {
    print_warning "EMERGENCY CYCLES DISTRIBUTION"
    print_warning "This will distribute minimum cycles to all critical canisters"
    
    local wallet_balance
    wallet_balance=$(get_wallet_balance)
    
    print_cycles "Wallet balance: $(format_cycles "$wallet_balance")"
    
    local emergency_amount=200000000000  # 200B cycles minimum
    local critical_canisters=()
    
    # Find critical canisters
    for canister in "${!CANISTER_PROFILES[@]}"; do
        local status
        status=$(check_canister_status "$canister")
        
        if [[ "$status" == "CRITICAL" || "$status" == "OFFLINE" ]]; then
            critical_canisters+=("$canister")
        fi
    done
    
    if [ ${#critical_canisters[@]} -eq 0 ]; then
        print_success "No critical canisters found!"
        return 0
    fi
    
    local total_needed=$((${#critical_canisters[@]} * emergency_amount))
    
    if [ "$wallet_balance" -lt "$total_needed" ]; then
        print_error "Insufficient cycles for emergency distribution!"
        print_error "Need: $(format_cycles "$total_needed")"
        print_error "Have: $(format_cycles "$wallet_balance")"
        exit 1
    fi
    
    print_warning "Critical canisters: ${critical_canisters[*]}"
    print_warning "Will distribute $(format_cycles "$emergency_amount") to each"
    
    read -p "Proceed with emergency distribution? (yes/no): " confirm
    if [[ $confirm != "yes" ]]; then
        echo "Emergency distribution cancelled."
        exit 0
    fi
    
    for canister in "${critical_canisters[@]}"; do
        print_status "Emergency top-up for $canister..."
        
        if dfx canister deposit-cycles "$emergency_amount" "$canister" --network "$NETWORK"; then
            print_success "✅ $canister emergency top-up complete"
        else
            print_error "❌ Failed emergency top-up for $canister"
        fi
    done
    
    print_success "Emergency distribution complete!"
}

# Main execution
case "$ACTION" in
    "status")
        show_status
        ;;
    "monitor")
        monitor_cycles
        ;;
    "distribute")
        distribute_cycles
        ;;
    "top-up")
        top_up_canister "$CANISTER" "$AMOUNT"
        ;;
    "balance")
        wallet_balance=$(get_wallet_balance)
        print_cycles "Wallet Balance: $(format_cycles "$wallet_balance") cycles"
        ;;
    "emergency")
        emergency_distribution
        ;;
    *)
        print_error "Unknown action: $ACTION"
        show_usage
        exit 1
        ;;
esac 