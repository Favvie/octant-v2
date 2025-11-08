# Yield Distribution System

A gas-efficient, Merkle-proof-based system for distributing yield generated from Aave vaults to contributors.

## Overview

The yield distribution system consists of three main components:

1. **YieldDistributor Contract** - Smart contract for managing distribution epochs and claiming
2. **Distribution Scripts** - Off-chain scripts for calculating allocations and generating Merkle trees
3. **Direct Claiming** - Contributors claim their yield using Merkle proofs (no pre-registration required)

## Architecture

```
Aave Yield → Strategy Profit → DragonRouter Shares
                                       ↓
                          [Withdraw & Convert to Asset]
                                       ↓
                            [YieldDistributor Contract]
                                       ↓
                     Epoch N: Merkle Root + Total Amount
                                       ↓
                           Contributors Claim with Proof
```

## Key Features

- ✅ **No Pre-registration** - Contributors claim directly with proofs
- ✅ **Gas Efficient** - Merkle proof verification instead of storing all allocations on-chain
- ✅ **Epoch-based** - Support for multiple distribution periods
- ✅ **Multi-asset** - Distribute any ERC20 token (USDC, DAI, etc.)
- ✅ **Flexible Allocation** - Equal distribution or custom weighted allocation
- ✅ **Anti-double-claim** - Prevents claiming twice in the same epoch
- ✅ **Batch Claiming** - Claim from multiple epochs in one transaction

## Contracts

### YieldDistributor

**Location**: `src/distribution/YieldDistributor.sol`

**Key Functions**:

```solidity
// Create new distribution epoch (owner only)
function createEpoch(
    bytes32 merkleRoot,
    uint256 totalAmount,
    address asset,
    uint256 startTime,
    uint256 endTime
) external onlyOwner returns (uint256 epochId)

// Claim yield for single epoch
function claim(
    uint256 epochId,
    uint256 amount,
    bytes32[] calldata proof
) external

// Claim yield from multiple epochs
function claimMultiple(
    uint256[] calldata epochIds,
    uint256[] calldata amounts,
    bytes32[][] calldata proofs
) external

// Cancel an epoch (owner only)
function cancelEpoch(uint256 epochId) external onlyOwner

// Emergency withdraw (owner only)
function emergencyWithdraw(
    address asset,
    uint256 amount,
    address to
) external onlyOwner
```

## Scripts

### 1. Calculate Distribution

**Script**: `scripts/calculate-yield-distribution.ts`

**Purpose**: Calculate how much yield each contributor should receive.

**Configuration**: Create `data/distribution-config.json`:

```json
{
  "epochId": 1,
  "asset": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  "assetSymbol": "USDC",
  "decimals": 6,
  "totalYield": "1000000000",
  "strategy": "equal",
  "startTime": 1699999999,
  "endTime": 0
}
```

**Strategies**:
- `equal` - Equal distribution among all contributors
- `custom` - Custom weighted distribution (requires `customWeights` object)

**Run**:
```bash
cd scripts
npm run calculate-distribution
```

**Output**: `data/distributions/epoch-{epochId}.json`

### 2. Generate Distribution Merkle Tree

**Script**: `scripts/generate-distribution-merkle.ts`

**Purpose**: Generate Merkle tree and proofs for the distribution.

**Run**:
```bash
cd scripts
npm run generate-distribution-merkle [epochId]
```

**Output**:
- `data/merkle-trees/epoch-{epochId}-merkle.json` - Complete tree with all proofs
- `data/merkle-trees/epoch-{epochId}-root.txt` - Just the root hash
- `data/merkle-trees/epoch-{epochId}-proofs/{github}.json` - Individual proof files

## Complete Workflow

### Step 1: Setup Contributors

Ensure you have contributors with wallet addresses in `data/contributors.json`:

```json
{
  "contributors": [
    {
      "github": "alice",
      "wallet": "0x742d35Cc6634C0532925a3b844Bc454e4438f44e",
      "totalScore": 54,
      "eligible": true
    }
  ]
}
```

### Step 2: Calculate Distribution

Create `data/distribution-config.json` with your configuration:

```json
{
  "epochId": 1,
  "asset": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  "assetSymbol": "USDC",
  "decimals": 6,
  "totalYield": "1000000000",
  "strategy": "equal",
  "startTime": 1699999999,
  "endTime": 0
}
```

Run the calculation:

```bash
cd scripts
npm run calculate-distribution
```

### Step 3: Generate Merkle Tree

```bash
npm run generate-distribution-merkle 1
```

This outputs:
- Merkle root for contract deployment
- Individual proof files for each contributor

### Step 4: Deploy YieldDistributor (if not already deployed)

```bash
forge script script/YieldDistributor.s.sol:YieldDistributorDeployScript \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Step 5: Fund the Contract

Transfer the total distribution amount to the YieldDistributor contract:

```solidity
IERC20(USDC).transfer(distributorAddress, totalAmount);
```

### Step 6: Create Epoch On-Chain

Using the Merkle root from step 3:

```solidity
distributor.createEpoch(
    merkleRoot,      // From epoch-1-root.txt
    totalAmount,     // 1000000000 (1000 USDC with 6 decimals)
    assetAddress,    // USDC address
    startTime,       // Unix timestamp
    endTime          // Unix timestamp or 0 for no expiry
);
```

### Step 7: Distribute Proof Files to Contributors

Share the individual proof files with contributors:
- `data/merkle-trees/epoch-1-proofs/alice.json`
- `data/merkle-trees/epoch-1-proofs/bob.json`
- etc.

### Step 8: Contributors Claim

Each contributor can claim their yield using their proof:

```solidity
// From alice.json proof file
uint256 epochId = 1;
uint256 amount = 250000000; // 250 USDC
bytes32[] memory proof = [...]; // From proof file

distributor.claim(epochId, amount, proof);
```

## Example Distribution Config

### Equal Distribution

```json
{
  "epochId": 1,
  "asset": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  "assetSymbol": "USDC",
  "decimals": 6,
  "totalYield": "1000000000",
  "strategy": "equal",
  "startTime": 1699999999,
  "endTime": 0
}
```

### Custom Weighted Distribution

```json
{
  "epochId": 2,
  "asset": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  "assetSymbol": "USDC",
  "decimals": 6,
  "totalYield": "2000000000",
  "strategy": "custom",
  "customWeights": {
    "alice": 2,
    "bob": 3,
    "charlie": 1
  },
  "startTime": 1699999999,
  "endTime": 1702591999
}
```

In this example:
- Bob gets 50% (3/6)
- Alice gets 33.3% (2/6)
- Charlie gets 16.7% (1/6)

## Testing

Run the comprehensive test suite:

```bash
forge test --match-contract YieldDistributor -vvv
```

**Test Coverage**:
- ✅ Epoch creation and management
- ✅ Single and multi-contributor claiming
- ✅ Double-claim prevention
- ✅ Invalid proof rejection
- ✅ Epoch expiry handling
- ✅ Emergency withdrawals
- ✅ Full distribution flow

## Security Considerations

1. **Merkle Proof Verification** - Uses OpenZeppelin's battle-tested MerkleProof library
2. **Reentrancy Protection** - ReentrancyGuard on all claim functions
3. **Owner Controls** - Only owner can create epochs and emergency withdraw
4. **No Upgradability** - Immutable contract for security
5. **Double-claim Prevention** - Mapping tracks claimed status per epoch per address

## Gas Optimization

- **Merkle Proofs**: O(log n) verification vs O(n) storage
- **Batch Claiming**: Claim multiple epochs in one transaction
- **Minimal Storage**: Only stores epoch metadata, not individual allocations

## Frontend Integration

### Verify Proof Before Claiming

```typescript
import { ethers } from 'ethers';

// Load proof file
const proofData = await fetch(`/proofs/epoch-1/alice.json`).then(r => r.json());

// Verify proof off-chain first
const isValid = await distributor.verifyClaim(
  proofData.epochId,
  proofData.wallet,
  proofData.amount,
  proofData.proof
);

if (isValid) {
  // Submit claim transaction
  await distributor.claim(
    proofData.epochId,
    proofData.amount,
    proofData.proof
  );
}
```

### Check Claim Status

```typescript
const hasClaimed = await distributor.hasClaimedForEpoch(epochId, userAddress);
```

### Get Epoch Info

```typescript
const epoch = await distributor.getEpoch(epochId);
console.log('Total:', epoch.totalAmount);
console.log('Claimed:', epoch.claimedAmount);
console.log('Remaining:', epoch.totalAmount - epoch.claimedAmount);
```

## File Structure

```
octant-v2/
├── src/
│   ├── distribution/
│   │   └── YieldDistributor.sol              # Main contract
│   └── test/
│       └── distribution/
│           ├── YieldDistributorSetup.sol      # Test setup
│           └── YieldDistributor.t.sol         # Test suite
├── script/
│   └── YieldDistributor.s.sol                 # Deployment script
├── scripts/
│   ├── calculate-yield-distribution.ts        # Calculate allocations
│   ├── generate-distribution-merkle.ts        # Generate Merkle tree
│   └── package.json                           # NPM dependencies
└── data/
    ├── distribution-config.json               # Distribution configuration
    ├── distributions/
    │   └── epoch-{N}.json                     # Calculated allocations
    └── merkle-trees/
        ├── epoch-{N}-merkle.json              # Complete Merkle tree
        ├── epoch-{N}-root.txt                 # Root hash only
        └── epoch-{N}-proofs/
            └── {github}.json                  # Individual proofs
```

## Troubleshooting

### "InsufficientBalance" error when creating epoch

**Solution**: Fund the YieldDistributor contract with the asset tokens before calling `createEpoch()`.

```solidity
IERC20(asset).transfer(distributorAddress, totalAmount);
```

### "InvalidProof" error when claiming

**Solution**: Ensure the proof matches the Merkle root and allocation for that specific epoch.

Verify the proof:
```solidity
bool valid = distributor.verifyClaim(epochId, wallet, amount, proof);
```

### "AlreadyClaimed" error

**Solution**: User has already claimed from this epoch. Check claim status:

```solidity
bool hasClaimed = distributor.hasClaimedForEpoch(epochId, userAddress);
```

## Future Enhancements

Potential improvements for future versions:

- [ ] Multiple asset support per epoch
- [ ] Automatic dragonRouter share redemption
- [ ] Delegation support (claim on behalf of)
- [ ] Merkle root rotation for updating allocations
- [ ] Integration with governance for epoch approval

## License

MIT
