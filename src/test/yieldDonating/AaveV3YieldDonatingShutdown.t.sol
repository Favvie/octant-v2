// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {AaveV3YieldDonatingSetup} from "./AaveV3YieldDonatingSetup.sol";

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

contract AaveV3YieldDonatingShutdownTest is AaveV3YieldDonatingSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown(), "Strategy should be shutdown");

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Redeem all shares
        vm.prank(user);
        strategy.redeem(strategy.balanceOf(user), user, user);

        assertApproxEqAbs(asset.balanceOf(user), balanceBefore + _amount, 10, "!final balance");
    }

    function test_shutdownWithProfit(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Generate some yield
        simulateYield();

        uint256 assetsBeforeShutdown = strategy.totalAssets();
        assertGt(assetsBeforeShutdown, _amount, "Should have gained value");

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown(), "Strategy should be shutdown");

        // After shutdown, report should still work to realize final profits
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0, "Should have profit");
        assertEq(loss, 0, "Should not have loss");

        // Dragon should have received profit shares
        assertGt(strategy.balanceOf(dragonRouter), 0, "Dragon should have shares");

        // User can still withdraw
        uint256 userShares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(userShares, user, user);

        // User should receive approximately their original deposit
        assertApproxEqAbs(asset.balanceOf(user), _amount, _amount / 100, "!user balance");
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
