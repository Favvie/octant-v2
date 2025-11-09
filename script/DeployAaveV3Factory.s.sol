// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {
    AaveV3YieldDonatingStrategyFactory
} from "../src/strategies/yieldDonating/AaveV3YieldDonatingStrategyFactory.sol";

contract DeployAaveV3Factory is Script {
    function run() external {
        vm.startBroadcast();

        address management = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;
        address donationAddress = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;
        address keeper = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;
        address emergencyAdmin = 0xFDb60A0e05539aA30acba38813cF6123B8780b04;

        // Set the address of the pre-deployed YieldDonatingTokenizedStrategy here
        address tokenizedStrategyAddress = vm.envAddress("TOKENIZED_STRATEGY_ADDRESS");

        AaveV3YieldDonatingStrategyFactory factory = new AaveV3YieldDonatingStrategyFactory(
            management,
            donationAddress,
            keeper,
            emergencyAdmin,
            tokenizedStrategyAddress
        );

        vm.stopBroadcast();
    }
}
