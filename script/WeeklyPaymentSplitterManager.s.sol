// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/distribution/WeeklyPaymentSplitterManager.sol";

/**
 * @title WeeklyPaymentSplitterManagerDeployScript
 * @notice Deployment script for WeeklyPaymentSplitterManager
 *
 * Usage:
 * forge script script/WeeklyPaymentSplitterManager.s.sol:WeeklyPaymentSplitterManagerDeployScript \
 *   --rpc-url <RPC_URL> \
 *   --broadcast \
 *   --verify
 *
 * Environment variables:
 * - PAYMENT_SPLITTER_FACTORY: Octant's PaymentSplitterFactory address
 * - STRATEGY_ADDRESS: YieldDonatingStrategy address
 * - DRAGON_ROUTER_ADDRESS: DragonRouter address
 * - OWNER_ADDRESS: Manager owner address
 */
contract WeeklyPaymentSplitterManagerDeployScript is Script {
    function run() external {
        // Get addresses from environment
        address factory = vm.envAddress("PAYMENT_SPLITTER_FACTORY");
        address strategy = vm.envAddress("STRATEGY_ADDRESS");
        address dragonRouter = vm.envAddress("DRAGON_ROUTER_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        console.log("Deploying WeeklyPaymentSplitterManager...");
        console.log("Factory:", factory);
        console.log("Strategy:", strategy);
        console.log("DragonRouter:", dragonRouter);
        console.log("Owner:", owner);

        vm.startBroadcast();

        WeeklyPaymentSplitterManager manager = new WeeklyPaymentSplitterManager(
            factory,
            strategy,
            dragonRouter,
            owner
        );

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("WeeklyPaymentSplitterManager:", address(manager));
        console.log("\nNext steps:");
        console.log("1. Approve manager to spend dragonRouter's strategy shares:");
        console.log("   cast send", strategy, "\\");
        console.log("     'approve(address,uint256)' \\");
        console.log("     ", address(manager), "\\");
        console.log("      999999999999999999999999 \\");
        console.log("     --rpc-url $RPC_URL --private-key $DRAGON_ROUTER_KEY");
        console.log("\n2. Run weekly-distribution script to prepare first distribution");
    }
}
