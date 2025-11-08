// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../dependencies/octant-v2-core/src/factories/PaymentSplitterFactory.sol";
import "../dependencies/octant-v2-core/src/core/PaymentSplitter.sol";
import "../src/distribution/WeeklyPaymentSplitterManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployFullDemo
 * @notice Complete deployment script for hackathon demo on Tenderly mainnet fork
 *
 * This script:
 * 1. Deploys Octant's PaymentSplitterFactory
 * 2. Sets up mock Strategy and DragonRouter (for demo)
 * 3. Deploys WeeklyPaymentSplitterManager
 * 4. Tests with sample distribution from data/distributions/week-45-payment-splitter.json
 *
 * Usage:
 * forge script script/DeployFullDemo.s.sol:DeployFullDemo \
 *   --rpc-url https://virtual.mainnet.eu.rpc.tenderly.co/82c86106-662e-4d7f-a974-c311987358ff \
 *   --broadcast \
 *   --legacy
 */
contract DeployFullDemo is Script {
    // Mainnet USDC address (already deployed on mainnet fork)
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Mock addresses for demo
    address mockStrategy;
    address mockDragonRouter;

    PaymentSplitterFactory factory;
    WeeklyPaymentSplitterManager manager;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Deploying Full Hackathon Demo ===");
        console.log("Deployer:", deployer);
        console.log("Network: Tenderly Mainnet Fork");
        console.log("USDC Address:", USDC);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Octant's PaymentSplitterFactory
        console.log("Step 1: Deploying PaymentSplitterFactory (Octant infrastructure)...");
        factory = new PaymentSplitterFactory();
        console.log("  PaymentSplitterFactory:", address(factory));
        console.log("");

        // Step 2: Deploy Mock Strategy and DragonRouter
        console.log("Step 2: Setting up mock Strategy and DragonRouter...");
        mockStrategy = address(new MockStrategy(USDC));
        mockDragonRouter = address(new MockDragonRouter());
        console.log("  Mock Strategy:", mockStrategy);
        console.log("  Mock DragonRouter:", mockDragonRouter);
        console.log("");

        // Step 3: Deploy WeeklyPaymentSplitterManager
        console.log("Step 3: Deploying WeeklyPaymentSplitterManager (our innovation)...");
        manager = new WeeklyPaymentSplitterManager(
            address(factory),
            mockStrategy,
            mockDragonRouter,
            deployer // owner
        );
        console.log("  WeeklyPaymentSplitterManager:", address(manager));
        console.log("");

        // Step 4: Setup - Approve manager to spend strategy shares
        console.log("Step 4: Approving manager to spend strategy shares...");
        MockStrategy(mockStrategy).approve(address(manager), type(uint256).max);
        console.log("  Approval granted");
        console.log("");

        // Step 5: Fund mock strategy with USDC for demo
        console.log("Step 5: Funding strategy with 1000 USDC for demo...");
        // Note: On Tenderly fork, we can use vm.deal to get ETH, but for USDC we need to:
        // - Either swap ETH for USDC via Uniswap
        // - Or use Tenderly's custom methods to mint USDC
        // For now, we'll just log the address so user can fund it manually
        console.log("  Please fund this address with USDC: ", mockStrategy);
        console.log("  You can do this via Tenderly dashboard or cast send");
        console.log("");

        vm.stopBroadcast();

        // Print summary
        console.log("=== Deployment Complete! ===");
        console.log("");
        console.log("Deployed Addresses:");
        console.log("  PaymentSplitterFactory (Octant):", address(factory));
        console.log("  WeeklyPaymentSplitterManager:     ", address(manager));
        console.log("  Mock Strategy:                    ", mockStrategy);
        console.log("  Mock DragonRouter:                ", mockDragonRouter);
        console.log("");
        console.log("Next Steps:");
        console.log("1. Fund mock strategy with USDC:");
        console.log("   cast send", USDC, "\\");
        console.log("     'transfer(address,uint256)' \\");
        console.log("     ", mockStrategy, "\\");
        console.log("      1000000000 \\");  // 1000 USDC (6 decimals)
        console.log("     --rpc-url $TENDERLY_RPC_URL --private-key $PRIVATE_KEY");
        console.log("");
        console.log("2. Create first weekly distribution:");
        console.log("   cast send", address(manager), "\\");
        console.log("     'createWeeklyDistribution(uint256,address[],string[],uint256[])' \\");
        console.log("      45 \\");
        console.log("     '[0x742d35Cc6634C0532925a3b844Bc454e4438f44e,0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199,0xdD2FD4581271e230360230F9337D5c0430Bf44C0,0xbDA5747bFD65F08deb54cb465eB87D40e51B197E]' \\");
        console.log("     '[alice,bob,charlie,david]' \\");
        console.log("     '[54,48,32,20]' \\");
        console.log("     --rpc-url $TENDERLY_RPC_URL --private-key $PRIVATE_KEY");
        console.log("");
        console.log("3. Check deployed PaymentSplitter:");
        console.log("   cast call", address(manager), "\\");
        console.log("     'getPaymentSplitter(uint256)' \\");
        console.log("      45 \\");
        console.log("     --rpc-url $TENDERLY_RPC_URL");
        console.log("");
        console.log("Save these addresses to .env:");
        console.log("PAYMENT_SPLITTER_FACTORY=", address(factory));
        console.log("STRATEGY_ADDRESS=", mockStrategy);
        console.log("DRAGON_ROUTER_ADDRESS=", mockDragonRouter);
        console.log("WEEKLY_MANAGER_ADDRESS=", address(manager));
    }
}

/**
 * @notice Mock Strategy for demo purposes
 * Simulates a YieldDonatingStrategy that holds USDC
 */
contract MockStrategy {
    IERC20 public immutable asset;
    mapping(address => uint256) public balances;

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        // For demo: just allow the approval
        return true;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        // For demo: return all USDC balance
        assets = asset.balanceOf(address(this));
        if (assets > 0) {
            asset.transfer(receiver, assets);
        }
        return assets;
    }

    // Helper to fund strategy with USDC
    function fundWithUSDC(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }
}

/**
 * @notice Mock DragonRouter for demo purposes
 */
contract MockDragonRouter {
    // Empty contract - just needs to exist as an address
}
