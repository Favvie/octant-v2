# Deployment Guide - Tenderly Mainnet Fork

This guide walks you through deploying the Weekly Yield Distribution system to your Tenderly mainnet fork for the hackathon demo.

## Prerequisites

1. **Foundry installed locally**
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. **Tenderly Fork Access**
   - RPC URL: `https://virtual.mainnet.eu.rpc.tenderly.co/82c86106-662e-4d7f-a974-c311987358ff`
   - Access to Tenderly dashboard

3. **Private Key**
   - Use a test private key for deployment
   - Default Anvil key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## Step 1: Set Environment Variables

Create a `.env` file in the project root:

```bash
# Tenderly Mainnet Fork
TENDERLY_RPC_URL=https://virtual.mainnet.eu.rpc.tenderly.co/82c86106-662e-4d7f-a974-c311987358ff

# Use default Anvil key for testing (or your own test key)
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# USDC on mainnet (already on Tenderly fork)
USDC_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
```

## Step 2: Load Environment

```bash
source .env
export DEPLOYER=$(cast wallet address $PRIVATE_KEY)
echo "Deployer address: $DEPLOYER"
```

## Step 3: Fund Deployer with ETH (via Tenderly Dashboard)

Go to your Tenderly fork dashboard and use the "Fund Account" feature to send ETH to your deployer address:

1. Open https://dashboard.tenderly.co
2. Navigate to your fork
3. Click "Fund Account"
4. Paste deployer address: `$DEPLOYER`
5. Send 10 ETH

Or via CLI (if you have Tenderly CLI):
```bash
tenderly devnet fund-account --address $DEPLOYER --amount 10000000000000000000
```

## Step 4: Deploy Full Demo

```bash
# Deploy all contracts (Factory, Manager, Mock Strategy)
forge script script/DeployFullDemo.s.sol:DeployFullDemo \
  --rpc-url $TENDERLY_RPC_URL \
  --broadcast \
  --legacy \
  --slow

# Save the output addresses - you'll need them!
```

**Expected Output:**
```
Deployed Addresses:
  PaymentSplitterFactory (Octant): 0x...
  WeeklyPaymentSplitterManager:      0x...
  Mock Strategy:                     0x...
  Mock DragonRouter:                 0x...
```

**Save these to your .env:**
```bash
echo "PAYMENT_SPLITTER_FACTORY=0x..." >> .env
echo "STRATEGY_ADDRESS=0x..." >> .env
echo "DRAGON_ROUTER_ADDRESS=0x..." >> .env
echo "WEEKLY_MANAGER_ADDRESS=0x..." >> .env
```

## Step 5: Fund Strategy with USDC

The mock strategy needs USDC to distribute. You have two options:

### Option A: Via Tenderly Dashboard (Recommended)

1. Go to Tenderly dashboard → Your fork
2. Navigate to USDC contract: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
3. Use "Execute Function" → `transfer`
4. Recipient: `$STRATEGY_ADDRESS` (from deployment output)
5. Amount: `1000000000` (1000 USDC with 6 decimals)

### Option B: Via Cast (if you have USDC)

```bash
# First, get USDC from a whale address on mainnet fork
# Uniswap Universal Router has lots of USDC
USDC_WHALE=0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD

# Impersonate whale (only works on fork)
cast rpc anvil_impersonateAccount $USDC_WHALE --rpc-url $TENDERLY_RPC_URL

# Transfer USDC from whale to strategy
cast send $USDC_ADDRESS \
  "transfer(address,uint256)" \
  $STRATEGY_ADDRESS \
  1000000000 \
  --from $USDC_WHALE \
  --rpc-url $TENDERLY_RPC_URL \
  --unlocked

cast rpc anvil_stopImpersonatingAccount $USDC_WHALE --rpc-url $TENDERLY_RPC_URL
```

### Option C: Mint USDC (if Tenderly supports it)

```bash
# Try minting USDC directly (may not work on mainnet fork)
cast send $USDC_ADDRESS \
  "mint(address,uint256)" \
  $STRATEGY_ADDRESS \
  1000000000 \
  --rpc-url $TENDERLY_RPC_URL \
  --private-key $PRIVATE_KEY
```

## Step 6: Verify USDC Balance

```bash
cast call $USDC_ADDRESS \
  "balanceOf(address)(uint256)" \
  $STRATEGY_ADDRESS \
  --rpc-url $TENDERLY_RPC_URL

# Expected: 1000000000 (1000 USDC)
```

## Step 7: Create Weekly Distribution

Use the test data we prepared in `data/distributions/week-45-payment-splitter.json`:

```bash
# Contributors from test data
CONTRIBUTORS='["0x742d35Cc6634C0532925a3b844Bc454e4438f44e","0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199","0xdD2FD4581271e230360230F9337D5c0430Bf44C0","0xbDA5747bFD65F08deb54cb465eB87D40e51B197E"]'
GITHUB_NAMES='["alice","bob","charlie","david"]'
SHARES='[54,48,32,20]'

# Create distribution
cast send $WEEKLY_MANAGER_ADDRESS \
  "createWeeklyDistribution(uint256,address[],string[],uint256[])" \
  45 \
  "$CONTRIBUTORS" \
  "$GITHUB_NAMES" \
  "$SHARES" \
  --rpc-url $TENDERLY_RPC_URL \
  --private-key $PRIVATE_KEY \
  --gas-limit 5000000

# Save transaction hash for demo!
```

## Step 8: Get PaymentSplitter Address

```bash
# Get deployed PaymentSplitter address for week 45
PAYMENT_SPLITTER=$(cast call $WEEKLY_MANAGER_ADDRESS \
  "getPaymentSplitter(uint256)(address)" \
  45 \
  --rpc-url $TENDERLY_RPC_URL)

echo "Week 45 PaymentSplitter: $PAYMENT_SPLITTER"

# Save to .env
echo "PAYMENT_SPLITTER_WEEK_45=$PAYMENT_SPLITTER" >> .env
```

## Step 9: Verify Distribution

```bash
# Check Alice's releasable amount
cast call $PAYMENT_SPLITTER \
  "releasable(address,address)(uint256)" \
  $USDC_ADDRESS \
  0x742d35Cc6634C0532925a3b844Bc454e4438f44e \
  --rpc-url $TENDERLY_RPC_URL

# Expected: ~350649350 (54/154 * 1000 USDC = ~350.65 USDC)
```

## Step 10: Test Claim (Alice Claims Her Share)

```bash
# Alice claims her USDC
cast send $PAYMENT_SPLITTER \
  "release(address,address)" \
  $USDC_ADDRESS \
  0x742d35Cc6634C0532925a3b844Bc454e4438f44e \
  --rpc-url $TENDERLY_RPC_URL \
  --private-key $PRIVATE_KEY

# Check Alice's USDC balance
cast call $USDC_ADDRESS \
  "balanceOf(address)(uint256)" \
  0x742d35Cc6634C0532925a3b844Bc454e4438f44e \
  --rpc-url $TENDERLY_RPC_URL

# Should show ~350649350 (350.65 USDC)
```

## Deployment Summary

After completing all steps, you should have:

✅ **Deployed Contracts:**
- PaymentSplitterFactory (Octant infrastructure)
- WeeklyPaymentSplitterManager (your innovation)
- Mock Strategy (for demo)
- Week 45 PaymentSplitter (deployed via factory)

✅ **Test Distribution:**
- 4 contributors (alice, bob, charlie, david)
- 1000 USDC distributed proportionally
- Alice claimed ~350.65 USDC successfully

✅ **Ready for Hackathon Demo:**
- All transactions on Tenderly fork
- Can share Tenderly dashboard link
- Shows Octant integration (Factory, PaymentSplitter)
- Demonstrates weekly dynamic distribution

## Troubleshooting

### Issue: "Insufficient funds"
**Solution:** Fund deployer address with more ETH via Tenderly dashboard

### Issue: "Strategy has no USDC"
**Solution:** Fund strategy address using Option A, B, or C in Step 5

### Issue: "Transaction reverted"
**Solution:** Check gas limit, try adding `--gas-limit 5000000`

### Issue: "Factory not found"
**Solution:** Ensure PaymentSplitterFactory deployed successfully in Step 4

## Demo Presentation Points

When presenting to hackathon judges, highlight:

1. **Octant Integration** 🎯
   - Uses PaymentSplitterFactory (50k gas vs 300k)
   - Uses PaymentSplitter (battle-tested)
   - Shows deep ecosystem understanding

2. **Innovation** 💡
   - Weekly dynamic distributions (not static)
   - GitHub integration for contribution tracking
   - Automated workflow (GitHub Actions)

3. **Production-Ready** ✅
   - Comprehensive test suite
   - Full documentation
   - Real deployment on fork

4. **Gas Savings** 📉
   - 83% gas savings using factory
   - 13M gas saved per year (52 weeks)

## Next Steps for Production

1. Deploy to actual mainnet/testnet
2. Integrate with real Octant Strategy (not mock)
3. Set up GitHub Actions automation
4. Build frontend for contributors to claim
5. Add governance for allocation strategies

## Support

Questions? Check:
- `OCTANT_INTEGRATION.md` - Hackathon overview
- `README.md` - Project overview
- Smart contracts in `src/distribution/`

Good luck with your hackathon demo! 🚀
