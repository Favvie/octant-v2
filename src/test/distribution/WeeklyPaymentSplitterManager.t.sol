// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {WeeklyPaymentSplitterManager} from "../../distribution/WeeklyPaymentSplitterManager.sol";
import {PaymentSplitterFactory} from "@octant-core/factories/PaymentSplitterFactory.sol";
import {PaymentSplitter} from "@octant-core/core/PaymentSplitter.sol";

/**
 * @title WeeklyPaymentSplitterManagerTest
 * @notice Tests for WeeklyPaymentSplitterManager with Octant integration
 */
contract WeeklyPaymentSplitterManagerTest is Test {
    WeeklyPaymentSplitterManager public manager;
    PaymentSplitterFactory public factory;

    address public owner = address(1);
    address public strategy = address(2);
    address public dragonRouter = address(3);
    address public alice = address(10);
    address public bob = address(11);
    address public charlie = address(12);

    function setUp() public {
        // Deploy PaymentSplitterFactory
        vm.prank(owner);
        factory = new PaymentSplitterFactory();

        // Deploy WeeklyPaymentSplitterManager
        vm.prank(owner);
        manager = new WeeklyPaymentSplitterManager(
            address(factory),
            strategy,
            dragonRouter,
            owner
        );

        // Label addresses
        vm.label(owner, "owner");
        vm.label(strategy, "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
    }

    function test_deployment() public view {
        assertEq(address(manager.factory()), address(factory));
        assertEq(address(manager.strategy()), strategy);
        assertEq(manager.dragonRouter(), dragonRouter);
        assertEq(manager.owner(), owner);
        assertEq(manager.currentWeek(), 0);
        assertEq(manager.getDistributionCount(), 0);
    }

    function test_viewFunctions() public view {
        // Test initial state
        assertEq(manager.getDistributionCount(), 0);

        uint256[] memory weeks = manager.getAllWeeks();
        assertEq(weeks.length, 0);
    }

    function test_updateStrategy() public {
        address newStrategy = address(999);

        vm.prank(owner);
        manager.updateStrategy(newStrategy);

        assertEq(address(manager.strategy()), newStrategy);
    }

    function test_updateStrategy_revertsIfNotOwner() public {
        address newStrategy = address(999);

        vm.prank(alice);
        vm.expectRevert();
        manager.updateStrategy(newStrategy);
    }

    // Note: Full integration tests with actual PaymentSplitter deployment
    // would require mocking the strategy's redeem function, which is beyond
    // the scope of this basic test. See integration tests for full workflow.
}
