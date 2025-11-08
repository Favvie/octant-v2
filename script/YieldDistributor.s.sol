// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/distribution/YieldDistributor.sol";

/**
 * @title YieldDistributorDeployScript
 * @notice Deployment script for YieldDistributor contract
 *
 * Usage:
 * forge script script/YieldDistributor.s.sol:YieldDistributorDeployScript --rpc-url <RPC_URL> --broadcast --verify
 *
 * Environment variables:
 * - OWNER_ADDRESS: Address that will own the YieldDistributor contract
 */
contract YieldDistributorDeployScript is Script {
    function run() external {
        // Get owner address from environment or use deployer
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        console.log("Deploying YieldDistributor...");
        console.log("Owner:", owner);

        vm.startBroadcast();

        YieldDistributor distributor = new YieldDistributor(owner);

        vm.stopBroadcast();

        console.log("YieldDistributor deployed at:", address(distributor));
        console.log("Current Epoch ID:", distributor.currentEpochId());
    }
}
