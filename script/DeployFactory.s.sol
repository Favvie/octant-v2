// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {YieldDonatingStrategyFactory} from "../src/strategies/yieldDonating/YieldDonatingStrategyFactory.sol";

/**
 * @title DeployFactory
 * @notice Deploys the YieldDonatingStrategyFactory contract
 * @dev Run with: forge script script/DeployFactory.s.sol --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployFactory is Script {
    // Role addresses - configure these as needed
    address public constant MANAGEMENT = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;
    address public constant KEEPER = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;
    address public constant EMERGENCY_ADMIN = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;
    address public constant DONATION_ADDRESS = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;

    YieldDonatingStrategyFactory public factory;

    function run() public {
        console2.log("Deploying YieldDonatingStrategyFactory...");
        console2.log("Deployer address:", msg.sender);
        console2.log("Management:", MANAGEMENT);
        console2.log("Keeper:", KEEPER);
        console2.log("Emergency Admin:", EMERGENCY_ADMIN);
        console2.log("Donation Address:", DONATION_ADDRESS);
        console2.log("");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy the factory
        // Constructor params: (address _management, address _donationAddress, address _keeper, address _emergencyAdmin)
        factory = new YieldDonatingStrategyFactory(
            MANAGEMENT,
            DONATION_ADDRESS,
            KEEPER,
            EMERGENCY_ADMIN
        );

        // Stop broadcasting
        vm.stopBroadcast();

        // Log the result
        console2.log("");
        console2.log("========================================");
        console2.log("Deployment successful!");
        console2.log("========================================");
        console2.log("Factory address:", address(factory));
        console2.log("");
        console2.log("Add to .env:");
        console2.log("STRATEGY_FACTORY_ADDRESS=", address(factory));
        console2.log("");
    }
}
