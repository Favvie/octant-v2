#!/bin/bash
# Quick deployment script for Tenderly mainnet fork
# Run this on your local machine (requires Foundry installed)

set -e

echo "🚀 Deploying Weekly Yield Distribution to Tenderly Fork"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "💡 Copy .env.example and fill in TENDERLY_RPC_URL and PRIVATE_KEY"
    exit 1
fi

# Load environment
source .env

# Check required variables
if [ -z "$TENDERLY_RPC_URL" ]; then
    echo "❌ TENDERLY_RPC_URL not set in .env"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ PRIVATE_KEY not set in .env"
    exit 1
fi

# Get deployer address
DEPLOYER=$(cast wallet address $PRIVATE_KEY)
echo "📍 Deployer address: $DEPLOYER"
echo ""

# Check ETH balance
echo "💰 Checking ETH balance..."
BALANCE=$(cast balance $DEPLOYER --rpc-url $TENDERLY_RPC_URL)
echo "   Balance: $BALANCE wei"

if [ "$BALANCE" = "0" ]; then
    echo ""
    echo "⚠️  WARNING: Deployer has 0 ETH!"
    echo "📝 Fund this address via Tenderly dashboard:"
    echo "   https://dashboard.tenderly.co"
    echo "   Address: $DEPLOYER"
    echo "   Amount: 10 ETH"
    echo ""
    read -p "Press Enter once funded..."
fi

echo ""
echo "📦 Step 1: Deploying contracts..."
forge script script/DeployFullDemo.s.sol:DeployFullDemo \
  --rpc-url $TENDERLY_RPC_URL \
  --broadcast \
  --legacy \
  --slow

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "1. Save contract addresses from output to .env"
echo "2. Fund strategy with USDC (see DEPLOYMENT_GUIDE.md Step 5)"
echo "3. Create weekly distribution (see DEPLOYMENT_GUIDE.md Step 7)"
echo "4. Test claim functionality (see DEPLOYMENT_GUIDE.md Step 10)"
echo ""
echo "📚 Full guide: DEPLOYMENT_GUIDE.md"
