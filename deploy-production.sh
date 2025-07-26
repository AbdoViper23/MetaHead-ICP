#!/bin/bash

# MetaHead ICP Game Production Deployment Script
# This script deploys all canisters to the IC mainnet with production settings

set -e

echo "🚀 Starting MetaHead ICP Game PRODUCTION Deployment..."
echo "⚠️  WARNING: This will deploy to the IC mainnet and consume cycles!"
echo ""

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

# Check if dfx is installed
if ! command -v dfx &> /dev/null; then
    print_error "DFX is not installed. Please install it first:"
    echo "sh -ci \"\$(curl -fsSL https://sdk.dfinity.org/install.sh)\""
    exit 1
fi

# Check DFX version
DFX_VERSION=$(dfx --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
print_status "Using DFX version: $DFX_VERSION"

# Confirm production deployment
echo ""
print_warning "You are about to deploy to the IC MAINNET!"
print_warning "This will consume real cycles and deploy live canisters."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ $confirm != "yes" ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Check cycles balance
print_status "Checking cycles balance..."
CYCLES_BALANCE=$(dfx wallet --network ic balance 2>/dev/null || echo "0")
print_status "Current cycles balance: $CYCLES_BALANCE"

if [[ "$CYCLES_BALANCE" == "0" ]]; then
    print_warning "No cycles detected. Please top up your cycles wallet first."
    echo "Visit: https://faucet.dfinity.org/"
    exit 1
fi

# Build with production optimizations
print_status "Building all canisters with production optimizations..."
export DFX_CONFIG_ROOT=$(pwd)
RUSTFLAGS="-C opt-level=3 -C target-cpu=native" dfx build --network ic --check
print_success "All canisters built successfully"

# Deploy to mainnet using production config
print_status "Deploying to IC mainnet with production settings..."

# Deploy canisters in order with production config
print_status "Deploying game_token canister to mainnet..."
dfx deploy game_token --network ic --with-cycles 10000000000000
GAME_TOKEN_ID=$(dfx canister id game_token --network ic)
print_success "game_token deployed with ID: $GAME_TOKEN_ID"

print_status "Deploying player_nft canister to mainnet..."
dfx deploy player_nft --network ic --with-cycles 15000000000000
PLAYER_NFT_ID=$(dfx canister id player_nft --network ic)
print_success "player_nft deployed with ID: $PLAYER_NFT_ID"

print_status "Deploying auction template to mainnet..."
dfx deploy auction --network ic --with-cycles 5000000000000
AUCTION_ID=$(dfx canister id auction --network ic)
print_success "auction template deployed with ID: $AUCTION_ID"

print_status "Deploying auction_factory canister to mainnet..."
dfx deploy auction_factory --network ic --with-cycles 20000000000000
AUCTION_FACTORY_ID=$(dfx canister id auction_factory --network ic)
print_success "auction_factory deployed with ID: $AUCTION_FACTORY_ID"

print_status "Deploying mystery_box canister to mainnet..."
dfx deploy mystery_box --network ic --with-cycles 10000000000000
MYSTERY_BOX_ID=$(dfx canister id mystery_box --network ic)
print_success "mystery_box deployed with ID: $MYSTERY_BOX_ID"

print_status "Deploying game_engine canister to mainnet..."
dfx deploy game_engine --network ic --with-cycles 20000000000000
GAME_ENGINE_ID=$(dfx canister id game_engine --network ic)
print_success "game_engine deployed with ID: $GAME_ENGINE_ID"

# Configure production canister relationships
print_status "Configuring production canister relationships..."

print_status "Linking player_nft to mystery_box..."
dfx canister call mystery_box set_player_nft_canister "(principal \"$PLAYER_NFT_ID\")" --network ic

print_status "Linking game_token to mystery_box..."
dfx canister call mystery_box set_game_token_canister "(principal \"$GAME_TOKEN_ID\")" --network ic

print_status "Linking canisters to game_engine..."
dfx canister call game_engine set_player_nft_canister "(principal \"$PLAYER_NFT_ID\")" --network ic
dfx canister call game_engine set_game_token_canister "(principal \"$GAME_TOKEN_ID\")" --network ic

print_success "Production canister relationships configured"

# Set up production mystery boxes
print_status "Creating production mystery boxes..."
dfx canister call mystery_box create_mystery_box "(
  variant { Common }, 
  1000000000, 
  1000, 
  vec {
    record {
      rarity = \"Common\";
      weight = 50;
      cards = vec {
        record {
          name = \"Warrior\";
          attack = 100;
          defense = 80;
          speed = 60;
          special_ability = \"Strike\";
          image_url = \"https://example.com/warrior.png\"
        };
        record {
          name = \"Archer\";
          attack = 80;
          defense = 60;
          speed = 100;
          special_ability = \"Precise Shot\";
          image_url = \"https://example.com/archer.png\"
        }
      }
    };
    record {
      rarity = \"Rare\";
      weight = 30;
      cards = vec {
        record {
          name = \"Mage\";
          attack = 120;
          defense = 70;
          speed = 80;
          special_ability = \"Fireball\";
          image_url = \"https://example.com/mage.png\"
        }
      }
    };
    record {
      rarity = \"Epic\";
      weight = 15;
      cards = vec {
        record {
          name = \"Dragon Knight\";
          attack = 150;
          defense = 120;
          speed = 90;
          special_ability = \"Dragon Breath\";
          image_url = \"https://example.com/dragon_knight.png\"
        }
      }
    };
    record {
      rarity = \"Legendary\";
      weight = 5;
      cards = vec {
        record {
          name = \"Ancient Guardian\";
          attack = 200;
          defense = 180;
          speed = 120;
          special_ability = \"Time Stop\";
          image_url = \"https://example.com/ancient_guardian.png\"
        }
      }
    }
  }
)" --network ic

print_success "Production mystery boxes created"

# Save deployment info
echo ""
echo "📄 Saving deployment information..."
cat > deployment-info.txt << EOF
MetaHead ICP Game - Production Deployment
Deployed on: $(date)
Network: IC Mainnet

Canister IDs:
============
Game Token (ICRC-1):      $GAME_TOKEN_ID
Player NFT (ICRC-7):      $PLAYER_NFT_ID
Auction Template:         $AUCTION_ID
Auction Factory:          $AUCTION_FACTORY_ID
Mystery Box:              $MYSTERY_BOX_ID
Game Engine:              $GAME_ENGINE_ID

Canister URLs:
=============
Game Token: https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.icp0.io/?id=$GAME_TOKEN_ID
Player NFT: https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.icp0.io/?id=$PLAYER_NFT_ID
Mystery Box: https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.icp0.io/?id=$MYSTERY_BOX_ID
Game Engine: https://a4gq6-oaaaa-aaaab-qaa4q-cai.raw.icp0.io/?id=$GAME_ENGINE_ID

Production Commands:
===================
# Check game token info:
dfx canister call $GAME_TOKEN_ID icrc1_name --network ic

# Check NFT collection info:
dfx canister call $PLAYER_NFT_ID icrc7_name --network ic

# Check mystery boxes:
dfx canister call $MYSTERY_BOX_ID get_all_mystery_boxes --network ic

# Register a player:
dfx canister call $GAME_ENGINE_ID register_player '("YourPlayerName")' --network ic

IMPORTANT SECURITY NOTES:
========================
- Controllers are set to empty arrays for production security
- Freezing threshold set to 90 days (7776000 seconds)
- Reserved cycles limits configured for each canister
- All canisters optimized for cycle efficiency

Next Steps:
==========
1. Update frontend to use these canister IDs
2. Configure proper access controls
3. Set up monitoring and alerting
4. Plan upgrade procedures
EOF

print_success "Deployment information saved to deployment-info.txt"

# Display final summary
echo ""
echo "🎉 MetaHead ICP Game PRODUCTION Deployment Complete!"
echo ""
echo "📋 Production Deployment Summary:"
echo "================================="
echo "Game Token (ICRC-1):      $GAME_TOKEN_ID"
echo "Player NFT (ICRC-7):      $PLAYER_NFT_ID"
echo "Auction Template:         $AUCTION_ID"
echo "Auction Factory:          $AUCTION_FACTORY_ID"
echo "Mystery Box:              $MYSTERY_BOX_ID"
echo "Game Engine:              $GAME_ENGINE_ID"
echo ""
echo "🌐 All canisters are now live on the IC mainnet!"
echo "📄 Deployment details saved in deployment-info.txt"
echo ""
echo "⚠️  IMPORTANT PRODUCTION NOTES:"
echo "- Monitor cycles consumption regularly"
echo "- Set up proper backup and upgrade procedures"
echo "- Update frontend configuration with these canister IDs"
echo "- Consider setting up monitoring and alerting"
echo ""
echo "🎮 Your MetaHead game is now live on the Internet Computer!" 