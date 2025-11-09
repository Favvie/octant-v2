# Octant V2 Yield-Donating Strategy Development Framework

[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-white)](https://book.getfoundry.sh/)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.25-blue)](https://docs.soliditylang.org/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A comprehensive framework for building and deploying **yield-generating investment strategies** that automatically donate 100% of profits to public goods funding through the [Octant](https://octant.app) ecosystem. Built with Foundry, integrated with Aave V3, and featuring governance, contributor registries, and automated distribution systems.

## Table of Contents

- [Project Overview](#project-overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Environment Setup](#environment-setup)
- [Directory Structure](#directory-structure)
- [Core Components](#core-components)
  - [Yield Strategies](#yield-strategies)
  - [Governance System](#governance-system)
  - [Distribution System](#distribution-system)
  - [Contributor Registry](#contributor-registry)
- [Strategy Development Guide](#strategy-development-guide)
- [Deployment & Scripts](#deployment--scripts)
- [Weekly Operational Cycle](#weekly-operational-cycle)
- [Testing](#testing)
- [Common Implementation Examples](#common-implementation-examples)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Resources](#resources)

---

## Project Overview

**OctaCred** is a production-grade system that enables:

1. **Yield Generation**: Deploy user assets into DeFi protocols (Aave V3, Compound, Yearn, etc.) to generate yield
2. **Automated Donation**: 100% of profits are automatically donated to public goods funding
3. **Contributor Rewards**: Weekly distribution of yield among verified open-source GitHub contributors
4. **Transparent Governance**: NFT-based councils with quadratic voting mechanism
5. **Gas-Efficient Verification**: Merkle-proof based contributor registry with zero reliance on centralized services

### The Mission

Enable individuals and organizations to participate in public goods funding without sacrifice—their capital generates market-rate yield, and all profits are transparently donated to support open-source development.

### Key Statistics

- **No Performance Fees**: 0% fees charged to users
- **100% Profit Donation**: Every cent of yield goes to public goods
- **Gas Efficient**: Merkle-proof verification (~2,000 gas per registration)
- **Battle Tested**: Built on Octant's core infrastructure with extensive test coverage
- **Multi-Protocol**: Support for Aave, Compound, Yearn, and custom ERC4626 vaults

---

## Key Features

### Core Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Yield Generation** | Deploy assets to Aave V3, earn interest via rebasing aTokens | ✅ Production |
| **Profit Donation** | 100% automatic minting of profits to dragonRouter address | ✅ Production |
| **Loss Protection** | Optional burning of dragonRouter shares to protect users | ✅ Production |
| **Weekly Distribution** | PaymentSplitter per week for contributor yield splits | ✅ Production |
| **Multi-Strategy Factory** | Deploy multiple strategies for different assets | ✅ Production |

### Advanced Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Contributor Verification** | Merkle-based GitHub contributor registry | ✅ Production |
| **NFT-Based Governance** | Soulbound Ecosystem Lead NFTs for council voting | ✅ Production |
| **Quadratic Voting** | Square-root voting power with stake weighting | ✅ Production |
| **APR Calculations** | Real-time APR oracle for yield estimation | ✅ Production |
| **Emergency Shutdown** | Admin-controlled emergency withdrawal mechanisms | ✅ Production |
| **Mainnet Fork Testing** | Real Aave state verification with Foundry fork tests | ✅ Production |

---

## Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────┐
│                    USER INTERFACE LAYER                      │
│  (External: Web3 wallets, dApps connecting to contracts)   │
└────────────────────────┬────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐  ┌──────▼──────┐  ┌────▼──────┐
    │ Deposit │  │  Vote/Vote  │  │  Register │
    │  Assets │  │  Govern     │  │ Contributor
    └────┬────┘  └──────┬──────┘  └────┬──────┘
         │               │               │
         │      ┌────────┴──────────┐    │
         │      │                   │    │
    ┌────▼──────▼───┐    ┌──────────▼────▼────┐
    │  Yield        │    │ Governance &       │
    │  Strategies   │    │ Registry System    │
    │  (Aave, etc)  │    │ (NFT, Voting,      │
    └────┬──────┬───┘    │  Merkle Registry)  │
         │      │        └────────┬───────────┘
         │      │                 │
    ┌────▼──────▼─────────────────▼──┐
    │  Weekly Distribution System     │
    │  (PaymentSplitter Manager)      │
    └────┬──────────────────────┬─────┘
         │                      │
    ┌────▼────────┐      ┌──────▼──────┐
    │ Contributor │      │  Governance │
    │  Payouts    │      │   Execution │
    └─────────────┘      └─────────────┘
```

### Component Interaction Flow

```
1. DEPOSIT PHASE
   User Deposit USDC
   → Strategy._deployFunds()
   → Supply to Aave V3 Pool
   → Receive aUSDC (rebasing)
   → Mint strategy shares

2. YIELD GENERATION
   Time passes, interest accrues
   → aUSDC balance increases automatically
   → Profit = new_aUSDC - initial_aUSDC

3. HARVEST PHASE
   Keeper calls report()
   → Strategy._harvestAndReport()
   → Calculate total assets
   → Compare with last report
   → New profit detected
   → Mint profit shares → dragonRouter

4. DISTRIBUTION PHASE
   Manager redeems dragon shares
   → Convert profit to USDC
   → Deploy PaymentSplitter
   → Register contributors via Merkle proofs
   → Split yield among verified addresses

5. GOVERNANCE (OPTIONAL)
   Ecosystem Lead NFT holders vote
   → Propose parameter changes
   → Quadratic voting (√stake = power)
   → Execute via EcosystemGovernanceExecutor

6. WITHDRAWAL PHASE
   User withdraws shares
   → Strategy._freeFunds()
   → Redeem from Aave V3 Pool
   → Return principal + accrued yield
   → Profits stay with dragonRouter
```

---

## Getting Started

### Prerequisites

- **Foundry**: [Install from docs](https://book.getfoundry.sh/getting-started/installation)
  - Includes forge, cast, anvil, and chisel
  - WSL recommended for Windows users
- **Node.js**: v18+ (for TypeScript deployment scripts)
- **Git**: For cloning and managing submodules
- **GitHub Account**: For contributing (optional)

### Installation

```bash
# Clone the repository
git clone git@github.com:golemfoundation/octant-v2-strategy-foundry-mix.git
cd octant-v2-strategy-foundry-mix

# Install Solidity dependencies
forge install
forge soldeer install

# Install Node.js dependencies
npm install

# Verify Foundry installation
forge --version
```

### Environment Setup

1. **Create `.env` file** from template:
```bash
cp .env.example .env
```

2. **Configure environment variables**:
```env
# Mainnet RPC - Required for fork testing and mainnet deployments
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY

# Optional: Tenderly Fork for testing
TENDERLY_RPC_URL=https://rpc.tenderly.co/fork/YOUR_FORK_ID

# Test Asset Addresses (Mainnet)
TEST_ASSET_ADDRESS=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48    # USDC
TEST_YIELD_SOURCE=0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2    # Aave V3 Pool

# Deployment Configuration
DEPLOYMENT_PRIVATE_KEY=your_private_key_here
EXPLORER_API_KEY=your_etherscan_key_for_verification
```

3. **Verify setup**:
```bash
# Test that Foundry can compile
forge build

# Test that Node dependencies are installed
npm list --depth=0
```

---

## Directory Structure

```
octant-v2-strategy-foundry-mix/
│
├── src/
│   ├── strategies/yieldDonating/              # Core yield strategy contracts
│   │   ├── YieldDonatingStrategy.sol          # Abstract template for strategies
│   │   ├── AaveV3YieldDonatingStrategy.sol    # Aave V3 concrete implementation
│   │   ├── YieldDonatingStrategyFactory.sol   # Factory for deploying strategies
│   │   └── AaveV3YieldDonatingStrategyFactory.sol
│   │
│   ├── governance/                            # DAO & governance contracts
│   │   └── EcosystemGovernanceExecutor.sol    # Executes governance decisions
│   │
│   ├── mechanisms/                            # Voting & allocation mechanisms
│   │   └── EcosystemLeadVoting.sol            # NFT-gated quadratic voting
│   │
│   ├── registry/                              # Contributor verification
│   │   └── ContributorRegistry.sol            # Merkle-based GitHub registry
│   │
│   ├── nft/                                   # NFT contracts
│   │   └── EcosystemLeadNFT.sol               # Soulbound council NFTs (ERC-5192)
│   │
│   ├── distribution/                          # Yield distribution contracts
│   │   └── WeeklyPaymentSplitterManager.sol   # Manages weekly yield splits
│   │
│   ├── periphery/                             # Utility contracts
│   │   └── StrategyAprOracle.sol              # APR calculation utilities
│   │
│   ├── interfaces/                            # Contract interfaces
│   │   ├── IStrategyInterface.sol
│   │   ├── IERC5192.sol                       # Soulbound NFT standard
│   │   └── Aave/                              # Aave V3 interfaces
│   │
│   └── test/                                  # Comprehensive test suites
│       ├── yieldDonating/                     # Strategy tests
│       │   ├── YieldDonatingOperation.t.sol
│       │   ├── YieldDonatingSetup.sol
│       │   ├── AaveV3YieldDonatingOperation.t.sol
│       │   ├── AaveV3YieldDonatingSetup.sol
│       │   ├── AaveV3YieldDonatingShutdown.t.sol
│       │   └── YieldDonatingFunctionSignature.t.sol
│       ├── governance/
│       │   └── EcosystemLeadGovernance.t.sol
│       ├── registry/
│       │   ├── ContributorRegistry.t.sol
│       │   └── ContributorRegistry.integration.t.sol
│       └── distribution/
│           └── WeeklyPaymentSplitterManager.t.sol
│
├── script/                                    # Foundry scripts (.s.sol)
│   ├── DeployFactory.s.sol
│   ├── DeployAaveV3Factory.s.sol
│   ├── DeployEcosystemGovernance.s.sol
│   └── ContributorRegistry.s.sol
│
├── scripts/                                   # TypeScript deployment scripts (.ts)
│   ├── deploy-all.ts                          # End-to-end deployment
│   ├── deploy-strategy.ts                     # Deploy strategy via factory
│   ├── deploy-factory.ts                      # Deploy factory contracts
│   ├── deploy-governance.ts                   # Deploy governance system
│   ├── deploy-registry.ts                     # Deploy contributor registry
│   ├── weekly-distribution.ts                 # Weekly yield split execution
│   ├── run-weekly-cycle.ts                    # Complete weekly workflow
│   └── health-check.ts                        # System monitoring
│
├── dependencies/                              # Git submodule
│   └── octant-v2-core/                        # Core Octant infrastructure
│
├── Makefile                                   # Test/build automation
├── foundry.toml                               # Foundry configuration
├── tsconfig.json                              # TypeScript configuration
├── package.json                               # Node.js dependencies
├── deployment-config.json                     # Deployment state tracking
└── README.md                                  # This file
```

---

## Core Components

### Yield Strategies

Yield strategies are the heart of the system. They manage user capital and deploy it to external yield sources while ensuring all profits are donated.

#### **YieldDonatingStrategy** (Abstract Base)
[`src/strategies/yieldDonating/YieldDonatingStrategy.sol`](src/strategies/yieldDonating/YieldDonatingStrategy.sol)

Base contract defining the strategy interface. Inherits from Yearn's Tokenized Strategy v3.

**Key Methods You Must Implement**:
- `_deployFunds(uint256 amount)` - Deploy assets to yield source
- `_freeFunds(uint256 amount)` - Withdraw assets from yield source
- `_harvestAndReport()` - Calculate total assets and report profits

**Built-in Functionality**:
- Share minting/burning for deposits/withdrawals
- Automatic profit calculation and minting to dragonRouter
- Optional loss protection via share burning
- Emergency withdrawal support

#### **AaveV3YieldDonatingStrategy** (Concrete Implementation)
[`src/strategies/yieldDonating/AaveV3YieldDonatingStrategy.sol`](src/strategies/yieldDonating/AaveV3YieldDonatingStrategy.sol)

Supplies USDC to Aave V3 Lending Pool, earning interest through rebasing aTokens.

**How It Works**:
```
1. User deposits USDC
2. Strategy approves USDC to Aave V3 Pool
3. Calls aaveLendingPool.supply(usdc, amount)
4. Receives aUSDC (rebasing) in return
5. aUSDC balance grows automatically as interest accrues
6. On report(), difference = profit
7. Profit minted as strategy shares to dragonRouter
8. User can withdraw principal anytime
```

**Example Deposit Flow**:
```solidity
// User deposits 1,000 USDC
strategy.deposit(1000e6); // 1000 USDC (6 decimals)

// Strategy mints 1000 strategy shares to user
// Strategy calls: aaveLendingPool.supply(USDC, 1000e6)

// After 1 week, aUSDC grows to 1010 USDC worth
// strategy.report() is called (by keeper)
// Profit of 10 USDC detected
// 10 strategy shares minted to dragonRouter

// User can still withdraw 1000 shares anytime
// Gets back 1000 USDC, profits stay with dragonRouter
```

#### **Factory Contracts**
[`src/strategies/yieldDonating/YieldDonatingStrategyFactory.sol`](src/strategies/yieldDonating/YieldDonatingStrategyFactory.sol)

Gas-efficient deployment of multiple strategy instances.

---

### Governance System

#### **EcosystemLeadNFT** (Soulbound NFT)
[`src/nft/EcosystemLeadNFT.sol`](src/nft/EcosystemLeadNFT.sol)

Non-transferable (soulbound) council membership NFTs following ERC-5192 standard.

**Properties**:
- One NFT per address (governance right)
- Non-transferable (bound to address)
- Revokable by governance
- Gas-efficient storage with supply cap

#### **EcosystemLeadVoting** (Quadratic Voting)
[`src/mechanisms/EcosystemLeadVoting.sol`](src/mechanisms/EcosystemLeadVoting.sol)

NFT-gated voting with quadratic voting mechanism (voting power = √stake).

**How It Works**:
```
1. Only NFT holders can vote
2. Voting power = square root of token stake
   - 100 tokens = 10 voting power
   - 10,000 tokens = 100 voting power
3. Prevents wealthy participants from dominating
4. Encourages broad participation
```

#### **EcosystemGovernanceExecutor**
[`src/governance/EcosystemGovernanceExecutor.sol`](src/governance/EcosystemGovernanceExecutor.sol)

Executes governance decisions: mint/revoke NFTs, update parameters, manage permissions.

---

### Distribution System

#### **WeeklyPaymentSplitterManager**
[`src/distribution/WeeklyPaymentSplitterManager.sol`](src/distribution/WeeklyPaymentSplitterManager.sol)

Orchestrates weekly yield distribution among contributors.

**Weekly Workflow**:
1. **Redeem** dragon shares from strategy to USDC
2. **Calculate** contributor allocations based on registry
3. **Deploy** new PaymentSplitter via Octant factory
4. **Distribute** USDC proportionally to each contributor
5. **Track** distributions for auditing

**Key Functions**:
```solidity
// Redeem profits and split among contributors
function redeemAndSplit(
    address strategy,
    uint256 sharesToRedeem,
    ContributorAllocation[] calldata allocations
) external;

// Get this week's distribution summary
function getWeeklyDistribution(uint256 week)
    external view returns (DistributionSummary);
```

---

### Contributor Registry

#### **ContributorRegistry** (Merkle-Based)
[`src/registry/ContributorRegistry.sol`](src/registry/ContributorRegistry.sol)

Gas-efficient GitHub contributor verification using Merkle proofs.

**How It Works**:
```
Off-Chain (Weekly):
  1. Query GitHub API for contributors
  2. Build Merkle tree with addresses + scores
  3. Publish root hash to GitHub/IPFS

On-Chain:
  1. Contributor calls register() with:
     - wallet address
     - GitHub username
     - contribution score
     - Merkle proof path
  2. Contract verifies proof against published root
  3. Stores contributor info in efficient storage
  4. Can claim yield only after registration
```

---

## Strategy Development Guide

This section covers developing new yield-donating strategies for other protocols.

### 1. Understanding the Template

The `YieldDonatingStrategy` template provides:

```solidity
abstract contract YieldDonatingStrategy is
    BaseStrategy,
    ERC165
{
    // Constructor parameters
    // Yield source interface
    // Three mandatory functions (marked TODO)
    // Optional functions you can override
    // Built-in profit/loss handling
}
```

### 2. Define Your Yield Source Interface

Create an interface for your specific protocol:

```solidity
// Example: ERC4626 Vault
interface IERC4626Vault {
    function deposit(uint256 assets, address receiver)
        external returns (uint256 shares);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    function convertToAssets(uint256 shares)
        external view returns (uint256);

    function balanceOf(address account)
        external view returns (uint256);
}
```

### 3. Implement Mandatory Functions

#### A. `_deployFunds(uint256 _amount)`

Deploy assets to your yield source:

```solidity
function _deployFunds(uint256 _amount) internal override {
    // Approve yield source if needed
    IERC20(asset).approve(address(yieldSource), _amount);

    // Deploy to your protocol
    IERC4626(address(yieldSource)).deposit(_amount, address(this));
}
```

#### B. `_freeFunds(uint256 _amount)`

Withdraw assets from your yield source:

```solidity
function _freeFunds(uint256 _amount) internal override {
    // Calculate shares needed to get target amount
    uint256 shares = IERC4626(address(yieldSource))
        .convertToShares(_amount);

    // Redeem from vault
    IERC4626(address(yieldSource)).redeem(
        shares,
        address(this), // receiver
        address(this)  // owner
    );
}
```

#### C. `_harvestAndReport()`

Calculate total assets (CRITICAL - profit depends on this):

```solidity
function _harvestAndReport()
    internal override
    returns (uint256 _totalAssets)
{
    // Get assets deployed in yield source
    uint256 shares = IERC4626(address(yieldSource))
        .balanceOf(address(this));
    uint256 deployedAssets = IERC4626(address(yieldSource))
        .convertToAssets(shares);

    // Get idle assets in strategy
    uint256 idleAssets = IERC20(address(asset))
        .balanceOf(address(this));

    // Return total
    _totalAssets = deployedAssets + idleAssets;

    // NOTE: BaseStrategy automatically:
    // 1. Compares _totalAssets with previous lastReport
    // 2. Calculates profit/loss
    // 3. Mints/burns dragonRouter shares accordingly
}
```

### 4. Optional Functions

Implement based on your protocol's needs:

#### `availableDepositLimit(address _owner)`

Cap deposits if protocol has limits:

```solidity
function availableDepositLimit(address)
    public view override
    returns (uint256)
{
    uint256 protocolCap = 1_000_000e6; // 1M USDC
    uint256 currentAssets = strategy.totalAssets();

    if (currentAssets >= protocolCap) {
        return 0;
    }

    return protocolCap - currentAssets;
}
```

#### `availableWithdrawLimit(address _owner)`

Limit withdrawals if protocol has liquidity constraints:

```solidity
function availableWithdrawLimit(address owner)
    public view override
    returns (uint256)
{
    // Most protocols allow full withdrawal
    return balanceOf(owner);
}
```

#### `_emergencyWithdraw(uint256 _amount)`

Emergency withdrawal when shutdown:

```solidity
function _emergencyWithdraw(uint256 _amount)
    internal override
{
    uint256 shares = IERC4626(address(yieldSource))
        .convertToShares(_amount);

    IERC4626(address(yieldSource)).redeem(
        shares,
        address(this),
        address(this)
    );
}
```

#### `_tend(uint256 _totalIdle)` and `_tendTrigger()`

Maintenance between reports (optional):

```solidity
function _tend(uint256 _totalIdle) internal override {
    if (_totalIdle > minDeployAmount) {
        _deployFunds(_totalIdle);
    }
}

function _tendTrigger() internal view override returns (bool) {
    return IERC20(address(asset)).balanceOf(address(this))
        > minDeployAmount;
}
```

### 5. Constructor Parameters

When deploying:

```solidity
YieldDonatingStrategy strategy = new AaveV3YieldDonatingStrategy(
    _asset: USDC_ADDRESS,
    _yieldSource: AAVE_V3_POOL_ADDRESS,
    _name: "USDC Aave V3 YieldDonating",
    _management: GOVERNANCE_ADDRESS,
    _keeper: KEEPER_ADDRESS,
    _emergencyAdmin: EMERGENCY_ADMIN_ADDRESS,
    _donationAddress: DRAGON_ROUTER_ADDRESS,
    _enableBurning: true,
    _tokenizedStrategyAddress: TOKENIZED_STRATEGY_ADDRESS
);
```

---

## Deployment & Scripts

### Foundry-Based Deployment

Deploy using Foundry scripts (`.s.sol`):

```bash
# Deploy strategy factory
forge script script/DeployFactory.s.sol --broadcast --verify

# Deploy Aave V3 factory
forge script script/DeployAaveV3Factory.s.sol --broadcast --verify

# Deploy governance system
forge script script/DeployEcosystemGovernance.s.sol --broadcast --verify

# Deploy contributor registry
forge script script/ContributorRegistry.s.sol --broadcast --verify
```
### Configuration Management

Deployments are tracked in `deployment-config.json`:

```json
{
  "network": {
    "name": "mainnet",
    "chainId": 1,
    "rpcUrl": "https://..."
  },
  "aave": {
    "poolAddress": "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
    "assetAddress": "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "assetSymbol": "USDC"
  },
  "contracts": {
    "strategyFactory": "0x...",
    "strategy": "0x...",
    "weeklyPaymentSplitterManager": "0x...",
    "ecosystemLeadNFT": "0x...",
    "contributorRegistry": "0x..."
  },
  "deploymentTimestamp": 1699999999
}
```
---

## Weekly Operational Cycle

The complete process of generating and distributing yield:

### Step-by-Step Flow

```
MONDAY (Harvest Day)
├─ Keeper calls strategy.report()
├─ _harvestAndReport() executed
├─ Profit = totalAssets - lastReport
├─ Profit shares minted to dragonRouter
└─ Event emitted with profit amount

TUESDAY (Distribution Setup)
├─ Manager fetches this week's contributors
├─ Manager calculates allocation percentages
├─ Manager redeems dragon shares to USDC
├─ Checks: profit ≥ min distribution threshold
└─ If too small, accumulates for next week

WEDNESDAY (Deploy Splitter)
├─ Manager calls deployPaymentSplitter()
├─ Octant factory creates new PaymentSplitter
├─ USDC transferred to splitter
├─ Allocations encoded into splitter
└─ Return splitter address

THURSDAY-SUNDAY (Contributors Claim)
├─ Contributors verify registration
├─ Call splitter.claim(beneficiary)
├─ Receive allocated portion of USDC
├─ Payouts tracked in system
└─ Weekly cycle completes
```

### Example: 1,000 USDC Weekly Profit

```
Total Profit: 1,000 USDC
Contributors: 100 verified GitHub contributors

Calculation (if equal split):
├─ Per contributor: 1,000 / 100 = 10 USDC
├─ Top contributor (10% higher): 11 USDC
├─ Median contributor: 10 USDC
└─ All payouts from single splitter contract

If Contribution Weighted:
├─ Top 10%: Larger shares (weighted by contribution score)
├─ Middle 50%: Medium shares
└─ Bottom 40%: Smaller shares
```

### Monitoring Weekly Operations

```bash
# Check this week's distribution
npm run check:distribution -- --week=45

# Get distribution summary
cast call \
  0x<MANAGER_ADDRESS> \
  "getWeeklyDistribution(uint256)" 45

# Monitor strategy balance
cast call \
  0x<STRATEGY_ADDRESS> \
  "totalAssets()"
```

---

## Testing

### Test Structure

```
src/test/
├── yieldDonating/
│   ├── YieldDonatingSetup.sol              # Base fixtures
│   ├── YieldDonatingOperation.t.sol        # Core functionality
│   ├── AaveV3YieldDonatingSetup.sol
│   ├── AaveV3YieldDonatingOperation.t.sol  # Aave-specific tests
│   ├── AaveV3YieldDonatingShutdown.t.sol   # Emergency shutdown
│   └── YieldDonatingFunctionSignature.t.sol # Interface verification
├── governance/
│   └── EcosystemLeadGovernance.t.sol
├── registry/
│   ├── ContributorRegistry.t.sol
│   └── ContributorRegistry.integration.t.sol
└── distribution/
    └── WeeklyPaymentSplitterManager.t.sol
```

### Running Tests

```bash
# Run all tests
make test

# Run with fork
FORK=true make test

# Run specific test
make test-contract contract=AaveV3YieldDonatingOperation

# Run with gas report
make gas

# Run with coverage
make coverage

# Run with verbose traces
make trace

# Run specific test function
forge test --match-test testDepositAndWithdraw -vvv
```

### Test Configuration

Tests use mainnet fork at specific block height for accurate Aave V3 state:

```solidity
// From foundry.toml
[profile.default]
fork_block_number = 21100000  # Nov 2024
rpc_endpoints = { mainnet = "..." }
```

### Key Test Scenarios

All strategies should verify:

- ✅ **Deposits**: Assets deployed correctly
- ✅ **Withdrawals**: Assets freed correctly
- ✅ **Profit Distribution**: Profits minted to dragonRouter only
- ✅ **Loss Handling**: Shares burned if losses occur
- ✅ **Emergency Shutdown**: Assets withdrawn when emergency triggered
- ✅ **Limits**: Deposit/withdraw limits enforced
- ✅ **Integration**: Works with actual Aave state (fork tests)

### Writing Custom Tests

```solidity
// Example: Test your custom strategy
pragma solidity ^0.8.25;

import {YieldDonatingSetup} from "./YieldDonatingSetup.sol";

contract CustomStrategyTest is YieldDonatingSetup {
    function setUp() public override {
        super.setUp();
        // Additional setup for your protocol
    }

    function testCustomDeployAndHarvest() public {
        uint256 amount = 1000e6; // 1000 USDC

        // Deposit
        vm.startPrank(user);
        asset.approve(address(strategy), amount);
        uint256 shares = strategy.deposit(amount, user);
        vm.stopPrank();

        // Advance time and harvest
        skip(1 weeks);
        vm.startPrank(keeper);
        vm.expectEmit();
        emit StrategyProfit(uint256 profit);
        strategy.report();
        vm.stopPrank();

        // Verify profit distributed
        assertGt(strategy.balanceOf(dragonRouter), 0);
    }
}
```



### Tools & Utilities

- **Tenderly**: https://tenderly.co/ (contract inspection, simulation)
- **Etherscan**: https://etherscan.io (contract verification, block exploration)
- **Alchemy**: https://alchemy.com/ (RPC endpoints, APIs)
- **Cast**: https://book.getfoundry.sh/cast/ (CLI tool for blockchain interaction)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

