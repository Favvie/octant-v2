// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {WeeklyPaymentSplitterManager} from "../../distribution/WeeklyPaymentSplitterManager.sol";
import {PaymentSplitterFactory} from "@octant-core/factories/PaymentSplitterFactory.sol";
import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";

/**
 * @title MockStrategy
 * @notice Mock strategy for testing - implements only required functions
 */
contract MockStrategy {
    address public assetAddress;

    constructor(address _asset) {
        assetAddress = _asset;
    }

    function asset() external view returns (address) {
        return assetAddress;
    }
}

/**
 * @title WeeklyPaymentSplitterManagerTest
 * @notice Tests for WeeklyPaymentSplitterManager with Octant integration
 */
contract WeeklyPaymentSplitterManagerTest is Test {
    WeeklyPaymentSplitterManager public manager;
    PaymentSplitterFactory public factory;
    MockStrategy public mockStrategy;

    address public owner = address(1);
    address public usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public dragonRouter = address(3);
    address public alice = address(10);
    address public bob = address(11);
    address public charlie = address(12);

    function setUp() public {
        // Deploy PaymentSplitterFactory
        vm.prank(owner);
        factory = new PaymentSplitterFactory();

        // Deploy MockStrategy
        mockStrategy = new MockStrategy(usdc);

        // Deploy WeeklyPaymentSplitterManager
        vm.prank(owner);
        manager = new WeeklyPaymentSplitterManager(
            address(factory),
            address(mockStrategy),
            dragonRouter,
            owner
        );

        // Label addresses
        vm.label(owner, "owner");
        vm.label(address(mockStrategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
    }

    function test_deployment() public view {
        assertEq(address(manager.factory()), address(factory));
        assertEq(address(manager.strategy()), address(mockStrategy));
        assertEq(manager.dragonRouter(), dragonRouter);
        assertEq(manager.owner(), owner);
        assertEq(manager.currentWeek(), 0);
        assertEq(manager.getDistributionCount(), 0);
    }

    function test_viewFunctions() public view {
        // Test initial state
        assertEq(manager.getDistributionCount(), 0);

        uint256[] memory weekNumbers = manager.getAllWeeks();
        assertEq(weekNumbers.length, 0);
    }

    function test_updateStrategy() public {
        MockStrategy newMockStrategy = new MockStrategy(usdc);

        vm.prank(owner);
        manager.updateStrategy(address(newMockStrategy));

        assertEq(address(manager.strategy()), address(newMockStrategy));
    }

    function test_updateStrategy_revertsIfNotOwner() public {
        MockStrategy newMockStrategy = new MockStrategy(usdc);

        vm.prank(alice);
        vm.expectRevert();
        manager.updateStrategy(address(newMockStrategy));
    }

    // Note: Full integration tests with actual PaymentSplitter deployment
    // would require mocking the strategy's redeem function, which is beyond
    // the scope of this basic test. See integration tests for full workflow.
}