// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/registry/ContributorRegistry.sol";

/**
 * @title Deploy ContributorRegistry
 * @notice Deployment script for ContributorRegistry contract
 *
 * Usage:
 * 1. Get Merkle root: cat data/merkle-root.txt
 * 2. Set environment variables:
 *    export MERKLE_ROOT=0x1234...
 *    export OWNER_ADDRESS=0xYourAddress...
 * 3. Deploy:
 *    forge script script/DeployContributorRegistry.s.sol:DeployContributorRegistry --rpc-url $RPC_URL --broadcast
 */
contract DeployContributorRegistry is Script {
    function run() external {
        // Get Merkle root from environment variable
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");

        // Get owner address (defaults to msg.sender if not set)
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        console.log("Deploying ContributorRegistry...");
        console.log("Merkle Root:", vm.toString(merkleRoot));
        console.log("Owner:", owner);

        vm.startBroadcast();

        ContributorRegistry registry = new ContributorRegistry(merkleRoot, owner);

        vm.stopBroadcast();

        console.log("ContributorRegistry deployed at:", address(registry));
        console.log("\nNext steps:");
        console.log("1. Verify contract on Etherscan");
        console.log("2. Test registration with:");
        console.log("   cast send <registry> 'register(string,uint256,bytes32[])' ...");
    }
}
