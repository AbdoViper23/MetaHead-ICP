#!/bin/bash

# MetaHead ICP Game Deployment Script
# This script deploys all canisters in the correct order and configures their relationships

set -e

echo "🚀 Starting MetaHead ICP Game Deployment..."

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

# Check if dfx is running
if ! dfx ping > /dev/null 2>&1; then
    print_warning "DFX is not running. Starting local replica..."
    dfx start --background --clean
    print_success "Local replica started"
fi

# Build frontend first
print_status "Building frontend..."
./scripts/build-frontend.sh
print_success "Frontend built successfully"

# Build all canisters
print_status "Building all canisters..."
dfx build
print_success "All canisters built successfully"

# Deploy canisters in the correct order
print_status "Deploying core token canisters..."

# 1. Deploy Game Token (ICRC-1)
print_status "Deploying game_token canister..."
dfx deploy game_token
GAME_TOKEN_ID=$(dfx canister id game_token)
print_success "game_token deployed with ID: $GAME_TOKEN_ID"

# 2. Deploy Player NFT (ICRC-7)
print_status "Deploying player_nft canister..."
dfx deploy player_nft
PLAYER_NFT_ID=$(dfx canister id player_nft)
print_success "player_nft deployed with ID: $PLAYER_NFT_ID"

# 3. Deploy Auction Template
print_status "Deploying auction template..."
dfx deploy auction
AUCTION_ID=$(dfx canister id auction)
print_success "auction template deployed with ID: $AUCTION_ID"

# 4. Deploy Auction Factory
print_status "Deploying auction_factory canister..."
dfx deploy auction_factory
AUCTION_FACTORY_ID=$(dfx canister id auction_factory)
print_success "auction_factory deployed with ID: $AUCTION_FACTORY_ID"

# 5. Deploy Mystery Box
print_status "Deploying mystery_box canister..."
dfx deploy mystery_box
MYSTERY_BOX_ID=$(dfx canister id mystery_box)
print_success "mystery_box deployed with ID: $MYSTERY_BOX_ID"

# 6. Deploy Game Engine
print_status "Deploying game_engine canister..."
dfx deploy game_engine
GAME_ENGINE_ID=$(dfx canister id game_engine)
print_success "game_engine deployed with ID: $GAME_ENGINE_ID"

# Configure canister relationships
print_status "Configuring canister relationships..."

# Set NFT canister in mystery box
print_status "Linking player_nft to mystery_box..."
dfx canister call mystery_box set_player_nft_canister "(principal \"$PLAYER_NFT_ID\")"

# Set token canister in mystery box
print_status "Linking game_token to mystery_box..."
dfx canister call mystery_box set_game_token_canister "(principal \"$GAME_TOKEN_ID\")"

# Set canisters in game engine
print_status "Linking canisters to game_engine..."
dfx canister call game_engine set_player_nft_canister "(principal \"$PLAYER_NFT_ID\")"
dfx canister call game_engine set_game_token_canister "(principal \"$GAME_TOKEN_ID\")"

print_success "Canister relationships configured successfully"

# Create initial mystery boxes
print_status "Creating default mystery boxes..."

# Create a Common mystery box
dfx canister call mystery_box create_mystery_box "(
  variant { Common }, 
  1000000000, 
  100, 
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
)"

print_success "Default mystery box created"

# Display deployment summary
echo ""
echo "🎉 MetaHead ICP Game Deployment Complete!"
echo ""
echo "📋 Deployment Summary:"
echo "======================="
echo "Game Token (ICRC-1):      $GAME_TOKEN_ID"
echo "Player NFT (ICRC-7):      $PLAYER_NFT_ID"
echo "Auction Template:         $AUCTION_ID"
echo "Auction Factory:          $AUCTION_FACTORY_ID"
echo "Mystery Box:              $MYSTERY_BOX_ID"
echo "Game Engine:              $GAME_ENGINE_ID"
echo ""
echo "🔗 Frontend URLs (if deployed):"
echo "Local: http://localhost:4943/?canisterId=$(dfx canister id frontend)"
echo ""
echo "🧪 Quick Test Commands:"
echo "========================"
echo "# Register a player:"
echo "dfx canister call game_engine register_player '(\"YourPlayerName\")'"
echo ""
echo "# Check mystery boxes:"
echo "dfx canister call mystery_box get_all_mystery_boxes '()'"
echo ""
echo "# Check game token info:"
echo "dfx canister call game_token icrc1_name '()'"
echo ""
echo "# Check NFT collection info:"
echo "dfx canister call player_nft icrc7_name '()'"
echo ""
echo "🎮 Your MetaHead game is ready to play!"
echo "Visit the README.md for detailed usage instructions." 