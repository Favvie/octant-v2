# Aave v3 YieldDonating Strategy

## Overview

This is a complete implementation of an Aave v3 lending strategy for the Octant YieldDonating framework. The strategy deposits assets into Aave v3's lending pools to earn interest, and automatically donates 100% of the yield to the designated dragonRouter address (Octant's public goods funding pool).

## Architecture

### Core Contracts

#### AaveV3YieldDonatingStrategy.sol
**Location:** `src/strategies/yieldDonating/AaveV3YieldDonatingStrategy.sol`

The main strategy contract that implements:
- **_deployFunds()**: Supplies assets to Aave v3 pool via `IPool.supply()`
- **_freeFunds()**: Withdraws assets from Aave v3 pool via `IPool.withdraw()`
- **_harvestAndReport()**: Calculates total assets by checking aToken balance + idle assets
- **_emergencyWithdraw()**: Emergency function to pull all funds from Aave during shutdown

Key features:
- Immutable aToken reference for gas efficiency
- Validation of aToken/pool/asset relationships in constructor
- Automatic approval of Aave pool to spend strategy assets
- View functions for monitoring: `balanceOfAToken()`, `estimatedAPR()`

### Interfaces

#### IPool.sol
**Location:** `src/interfaces/Aave/IPool.sol`

Defines the Aave v3 Pool interface with:
- `supply()`: Deposit assets and receive aTokens
- `withdraw()`: Withdraw assets and burn aTokens
- `getReserveNormalizedIncome()`: Get reserve income (for future APR calculations)

#### IAToken.sol
**Location:** `src/interfaces/Aave/IAToken.sol`

Defines the aToken interface with:
- Standard ERC20 functions (inherited from IERC20)
- `UNDERLYING_ASSET_ADDRESS()`: Returns the underlying asset
- `POOL()`: Returns the Aave pool address

### Test Suite

#### AaveV3YieldDonatingSetup.sol
**Location:** `src/test/yieldDonating/AaveV3YieldDonatingSetup.sol`

Base test setup with:
- Mainnet fork configuration (defaults to Ethereum mainnet)
- USDC as default test asset with Aave v3 USDC pool
- Helper functions: `depositIntoStrategy()`, `mintAndDepositIntoStrategy()`, `simulateYield()`
- Pre-configured roles: user, keeper, management, dragonRouter, emergencyAdmin

#### AaveV3YieldDonatingOperation.t.sol
**Location:** `src/test/yieldDonating/AaveV3YieldDonatingOperation.t.sol`

Comprehensive operation tests:
- ✅ `test_setupStrategyOK()`: Verify strategy initialization
- ✅ `test_aaveIntegration()`: Verify Aave contract integration
- ✅ `test_operation()`: Full deposit → yield → report → withdraw cycle
- ✅ `test_profitableReport()`: Verify profit reporting and dragon share minting
- ✅ `test_withdrawal()`: Test partial withdrawals
- ✅ `test_emergencyWithdraw()`: Test emergency withdrawal functionality
- ✅ `test_multipleUsersDepositAndWithdraw()`: Multi-user scenarios
- ✅ `test_yieldDonationFlow()`: Verify yield donation mechanism

#### AaveV3YieldDonatingShutdown.t.sol
**Location:** `src/test/yieldDonating/AaveV3YieldDonatingShutdown.t.sol`

Shutdown and emergency tests:
- ✅ `test_shutdownCanWithdraw()`: Users can withdraw after shutdown
- ✅ `test_shutdownWithProfit()`: Final profit reporting during shutdown
- ✅ `test_emergencyWithdrawAll()`: Emergency admin can withdraw all funds
- ✅ `test_cannotDepositAfterShutdown()`: Deposits blocked after shutdown

## How It Works

### 1. Deposit Flow
```
User deposits USDC → Strategy receives USDC
                   → Strategy calls aavePool.supply()
                   → Strategy receives aUSDC (rebasing token)
                   → User receives strategy shares
```

### 2. Yield Accrual
```
Time passes → aUSDC balance increases (rebasing)
            → totalAssets() reflects higher value
```

### 3. Profit Reporting
```
Keeper calls report() → Strategy calculates profit
                      → Profit = (current aToken balance + idle) - last reported value
                      → New shares minted to dragonRouter
                      → User shares unchanged (value preserved)
```

### 4. Withdrawal Flow
```
User redeems shares → Strategy calculates asset amount
                    → Strategy calls aavePool.withdraw()
                    → aUSDC burned, USDC received
                    → USDC transferred to user
```

## Configuration

### Mainnet Addresses (Default)

- **Aave v3 Pool**: `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`
- **USDC**: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`
- **aUSDC**: `0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c`

### Environment Variables

Create a `.env` file:
```bash
ETH_RPC_URL=https://rpc.ankr.com/eth
# Or use your own RPC endpoint for better reliability
# ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
```

## Building and Testing

### Prerequisites
- Foundry (forge, cast, anvil)
- An Ethereum RPC endpoint (for mainnet fork testing)

### Build
```bash
forge build
```

### Run All Tests
```bash
make test
```

### Run Specific Test Contract
```bash
make test-contract contract=AaveV3YieldDonatingOperationTest
make test-contract contract=AaveV3YieldDonatingShutdownTest
```

### Run with Detailed Traces
```bash
make trace-contract contract=AaveV3YieldDonatingOperationTest
```

### Generate Gas Report
```bash
make gas
```

### Generate Coverage Report
```bash
make coverage-html
```

## Deployment

### Using the Constructor Directly

```solidity
AaveV3YieldDonatingStrategy strategy = new AaveV3YieldDonatingStrategy(
    0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2,  // aavePool
    0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c,  // aToken (aUSDC)
    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,  // asset (USDC)
    "Aave v3 USDC YieldDonating Strategy",         // name
    0x...,                                          // management
    0x...,                                          // keeper
    0x...,                                          // emergencyAdmin
    0x...,                                          // dragonRouter (donation address)
    true,                                           // enableBurning
    0x...                                           // tokenizedStrategyAddress
);
```

### Using a Factory (Recommended)

A factory contract can be created to standardize deployments across different assets.

## Supported Assets

This strategy can be deployed for any asset supported by Aave v3. Simply provide the correct:
- Asset address (e.g., USDC, USDT, DAI, WETH, etc.)
- Corresponding aToken address
- Aave v3 Pool address for the target network

### Multi-Chain Support

The strategy supports Aave v3 on multiple networks:
- **Ethereum**: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
- **Polygon**: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
- **Arbitrum**: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
- **Optimism**: 0x794a61358D6845594F94dc1DB02A252b5b4814aD
- **Avalanche**: 0x794a61358D6845594F94dc1DB02A252b5b4814aD

Update the test setup to fork different networks for testing.

## Security Considerations

### Implemented Safeguards

1. **Asset Validation**: Constructor verifies aToken matches the pool and underlying asset
2. **Immutable References**: aToken and yieldSource are immutable for security
3. **SafeERC20**: All token transfers use OpenZeppelin's SafeERC20
4. **Emergency Controls**: Emergency admin can shutdown and withdraw funds
5. **Role-Based Access**: Separate roles for management, keeper, and emergency admin

### Potential Risks

1. **Aave Protocol Risk**: Strategy depends on Aave v3 security
2. **Oracle Risk**: If using `estimatedAPR()`, oracle manipulation could affect decisions
3. **Liquidity Risk**: Large withdrawals may face Aave liquidity constraints
4. **Smart Contract Risk**: Standard smart contract vulnerabilities

### Recommendations

- Audit the strategy before mainnet deployment
- Start with smaller deposit limits
- Monitor Aave protocol health regularly
- Test thoroughly on testnets and forks before mainnet use
- Consider implementing deposit/withdrawal limits initially

## Future Enhancements

1. **APR Oracle**: Implement `estimatedAPR()` by integrating Aave's PoolDataProvider
2. **Reward Harvesting**: Add support for claiming and selling Aave rewards (stkAAVE)
3. **Supply Cap Monitoring**: Add checks for Aave supply caps to prevent failed deposits
4. **Health Factor Monitoring**: For strategies that might use borrowing
5. **Factory Contract**: Create a factory for easy multi-asset deployment

## Testing Results

All tests pass with mainnet fork:
- ✅ Strategy initialization and setup
- ✅ Deposit and withdrawal operations
- ✅ Profit generation and reporting
- ✅ Yield donation to dragonRouter
- ✅ Emergency shutdown procedures
- ✅ Multi-user interactions
- ✅ Edge cases and error handling

## License

MIT License - See LICENSE file for details

## Support

For questions or issues:
- GitHub Issues: [Repository Issues Page]
- Documentation: [Octant Documentation]
- Community: [Octant Discord/Forum]
