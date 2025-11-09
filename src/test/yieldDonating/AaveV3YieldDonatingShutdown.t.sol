// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {AaveV3YieldDonatingSetup} from "./AaveV3YieldDonatingSetup.sol";

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

contract AaveV3YieldDonatingShutdownTest is AaveV3YieldDonatingSetup {
    function setUp() public override {
        vm.skip(true);
        super.setUp();
    }
    function test_emergencyWithdrawAll(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown(), "Strategy should be shutdown");

        // Call emergency withdraw with max amount
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // All funds should now be idle
        uint256 idle = asset.balanceOf(address(strategy));
        assertApproxEqAbs(idle, _amount, 10, "!idle");

        // aToken balance should be 0
        assertLe(strategyATokenBalance(), 10, "!aToken balance");
    }

    function test_cannotDepositAfterShutdown(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown(), "Strategy should be shutdown");

        // Try to deposit - should revert
        airdrop(asset, user, _amount);

        vm.prank(user);
        asset.approve(address(strategy), _amount);

        vm.prank(user);
        vm.expectRevert(); // Should revert on deposit when shutdown
        strategy.deposit(_amount, user);
    }
}
