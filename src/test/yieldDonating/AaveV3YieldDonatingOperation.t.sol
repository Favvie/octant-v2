// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {AaveV3YieldDonatingSetup} from "./AaveV3YieldDonatingSetup.sol";

import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";

contract AaveV3YieldDonatingOperationTest is AaveV3YieldDonatingSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), dragonRouter);
        assertEq(strategy.keeper(), keeper);
    }

    function test_aaveIntegration() public {
        // Verify aToken is set correctly
        assertEq(address(aaveStrategy.aToken()), address(aToken));
        assertEq(address(aaveStrategy.yieldSource()), address(aavePool));
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Check that assets were deployed to Aave
        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Check aToken balance - should be approximately equal to deposit amount
        // (may have small difference due to Aave's rounding)
        uint256 aTokenBal = strategyATokenBalance();
        assertApproxEqAbs(aTokenBal, _amount, 10, "!aTokenBalance");

        // Skip time to simulate yield generation
        simulateYield();

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // We should have profit from Aave yield, no loss
        assertGt(profit, 0, "Expected profit");
        assertEq(loss, 0, "Unexpected loss");

        // After report, check that profit was minted to dragonRouter
        uint256 dragonShares = strategy.balanceOf(dragonRouter);
        assertGt(dragonShares, 0, "Dragon should have shares from profit");

        // Check total assets increased
        assertGt(strategy.totalAssets(), _amount, "Assets should have increased");

        // User should be able to withdraw their original deposit
        uint256 userShares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(userShares, user, user);

        // User should receive approximately their initial deposit
        // (may be slightly less due to rounding and any losses)
        uint256 userAssetBalance = asset.balanceOf(user);
        assertApproxEqAbs(userAssetBalance, _amount, _amount / 100, "!userBalance"); // Within 1%
    }

    function test_profitableReport(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Skip time to generate yield
        simulateYield();

        uint256 beforeDragonShares = strategy.balanceOf(dragonRouter);

        // Report
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0, "Should have profit");
        assertEq(loss, 0, "Should not have loss");

        // Dragon router should have received shares
        uint256 afterDragonShares = strategy.balanceOf(dragonRouter);
        assertGt(afterDragonShares, beforeDragonShares, "Dragon should have more shares");
    }

    function test_withdrawal(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 userShares = strategy.balanceOf(user);
        assertGt(userShares, 0, "User should have shares");

        // Withdraw half
        uint256 withdrawShares = userShares / 2;

        vm.prank(user);
        uint256 withdrawn = strategy.redeem(withdrawShares, user, user);

        assertGt(withdrawn, 0, "Should have withdrawn assets");
        assertApproxEqAbs(withdrawn, _amount / 2, _amount / 100, "!withdrawn amount");

        // Check remaining shares
        assertApproxEqAbs(strategy.balanceOf(user), userShares / 2, 1, "!remaining shares");
    }

    function test_emergencyWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertTrue(strategy.isShutdown(), "Strategy should be shutdown");

        // Emergency withdraw
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(_amount);

        // Assets should now be idle in the strategy
        uint256 idle = asset.balanceOf(address(strategy));
        assertApproxEqAbs(idle, _amount, 10, "!idle amount");

        // aToken balance should be 0 or very small
        assertLe(strategyATokenBalance(), 10, "aToken should be withdrawn");
    }

    function test_multipleUsersDepositAndWithdraw() public {
        address user2 = address(20);
        address user3 = address(30);

        uint256 amount1 = 100_000 * 10 ** decimals;
        uint256 amount2 = 200_000 * 10 ** decimals;
        uint256 amount3 = 150_000 * 10 ** decimals;

        // Multiple users deposit
        mintAndDepositIntoStrategy(strategy, user, amount1);
        mintAndDepositIntoStrategy(strategy, user2, amount2);
        mintAndDepositIntoStrategy(strategy, user3, amount3);

        uint256 totalDeposited = amount1 + amount2 + amount3;
        assertApproxEqAbs(strategy.totalAssets(), totalDeposited, 100, "!total deposited");

        // Generate yield
        simulateYield();

        // Report profit
        vm.prank(keeper);
        (uint256 profit,) = strategy.report();
        assertGt(profit, 0, "Should have profit");

        // All users withdraw
        vm.prank(user);
        strategy.redeem(strategy.balanceOf(user), user, user);

        vm.prank(user2);
        strategy.redeem(strategy.balanceOf(user2), user2, user2);

        vm.prank(user3);
        strategy.redeem(strategy.balanceOf(user3), user3, user3);

        // Dragon router should still have shares from profit
        assertGt(strategy.balanceOf(dragonRouter), 0, "Dragon should have profit shares");

        // Strategy should have minimal assets left (just dragon's share value + dust)
        // Dragon can also withdraw their shares if needed
    }

    function test_yieldDonationFlow() public {
        uint256 depositAmount = 1_000_000 * 10 ** decimals;

        // User deposits
        mintAndDepositIntoStrategy(strategy, user, depositAmount);

        // Skip time to accrue yield
        simulateYield();

        uint256 assetsBeforeReport = strategy.totalAssets();
        uint256 dragonSharesBefore = strategy.balanceOf(dragonRouter);

        // Report to realize profit
        vm.prank(keeper);
        (uint256 profit,) = strategy.report();

        assertGt(profit, 0, "Should have earned profit");

        // Dragon router should have received new shares representing the profit
        uint256 dragonSharesAfter = strategy.balanceOf(dragonRouter);
        uint256 newDragonShares = dragonSharesAfter - dragonSharesBefore;
        assertGt(newDragonShares, 0, "Dragon should receive profit shares");

        // The value of dragon's new shares should approximately equal the profit
        uint256 dragonShareValue = strategy.convertToAssets(newDragonShares);
        assertApproxEqAbs(dragonShareValue, profit, profit / 10, "Dragon share value should equal profit");

        // User's share value should remain approximately the same (their original deposit)
        uint256 userShares = strategy.balanceOf(user);
        uint256 userShareValue = strategy.convertToAssets(userShares);
        assertApproxEqAbs(userShareValue, depositAmount, depositAmount / 100, "User value preserved");
    }
}
