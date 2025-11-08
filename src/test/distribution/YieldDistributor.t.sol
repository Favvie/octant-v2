// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console2.sol";
import {YieldDistributorSetup} from "./YieldDistributorSetup.sol";
import {YieldDistributor} from "../../distribution/YieldDistributor.sol";

contract YieldDistributorTest is YieldDistributorSetup {
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_deployment() public view {
        assertEq(distributor.owner(), owner);
        assertEq(distributor.currentEpochId(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EPOCH CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_createEpoch() public {
        fundDistributor(totalAmount);

        vm.prank(owner);
        uint256 epochId = distributor.createEpoch(
            merkleRoot, totalAmount, address(usdc), block.timestamp, 0 // No expiry
        );

        assertEq(epochId, 1);
        assertEq(distributor.currentEpochId(), 1);

        YieldDistributor.Epoch memory epoch = distributor.getEpoch(1);
        assertEq(epoch.merkleRoot, merkleRoot);
        assertEq(epoch.totalAmount, totalAmount);
        assertEq(epoch.asset, address(usdc));
        assertEq(epoch.startTime, block.timestamp);
        assertEq(epoch.endTime, 0);
        assertEq(epoch.claimedAmount, 0);
        assertTrue(epoch.active);
    }

    function test_createEpoch_withExpiry() public {
        fundDistributor(totalAmount);

        uint256 expiryTime = block.timestamp + 30 days;

        vm.prank(owner);
        uint256 epochId = distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, expiryTime);

        YieldDistributor.Epoch memory epoch = distributor.getEpoch(epochId);
        assertEq(epoch.endTime, expiryTime);
    }

    function test_createMultipleEpochs() public {
        // Create first epoch
        fundDistributor(totalAmount);
        vm.prank(owner);
        uint256 epoch1 = distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, 0);

        // Create second epoch
        fundDistributor(totalAmount);
        vm.prank(owner);
        uint256 epoch2 = distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, 0);

        assertEq(epoch1, 1);
        assertEq(epoch2, 2);
        assertEq(distributor.currentEpochId(), 2);
    }

    function test_createEpoch_revertsIfNotOwner() public {
        fundDistributor(totalAmount);

        vm.prank(alice);
        vm.expectRevert();
        distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, 0);
    }

    function test_createEpoch_revertsIfInsufficientBalance() public {
        // Don't fund the distributor

        vm.prank(owner);
        vm.expectRevert(YieldDistributor.InsufficientBalance.selector);
        distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, 0);
    }

    function test_createEpoch_revertsIfInvalidParameters() public {
        fundDistributor(totalAmount);

        // Invalid merkle root
        vm.prank(owner);
        vm.expectRevert("Invalid merkle root");
        distributor.createEpoch(bytes32(0), totalAmount, address(usdc), block.timestamp, 0);

        // Invalid total amount
        vm.prank(owner);
        vm.expectRevert("Invalid total amount");
        distributor.createEpoch(merkleRoot, 0, address(usdc), block.timestamp, 0);

        // Invalid asset
        vm.prank(owner);
        vm.expectRevert("Invalid asset");
        distributor.createEpoch(merkleRoot, totalAmount, address(0), block.timestamp, 0);

        // Invalid start time
        vm.prank(owner);
        vm.expectRevert("Invalid start time");
        distributor.createEpoch(merkleRoot, totalAmount, address(usdc), 0, 0);

        // Invalid end time
        vm.prank(owner);
        vm.expectRevert("Invalid end time");
        distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, block.timestamp - 1);
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claim() public {
        uint256 epochId = createTestEpoch();

        uint256 beforeBalance = usdc.balanceOf(alice);

        vm.prank(alice);
        distributor.claim(epochId, aliceAmount, proofs[alice]);

        uint256 afterBalance = usdc.balanceOf(alice);
        assertEq(afterBalance - beforeBalance, aliceAmount);
        assertTrue(distributor.hasClaimedForEpoch(epochId, alice));
    }

    function test_claim_multipleContributors() public {
        uint256 epochId = createTestEpoch();

        // Alice claims
        vm.prank(alice);
        distributor.claim(epochId, aliceAmount, proofs[alice]);
        assertEq(usdc.balanceOf(alice), aliceAmount);

        // Bob claims
        vm.prank(bob);
        distributor.claim(epochId, bobAmount, proofs[bob]);
        assertEq(usdc.balanceOf(bob), bobAmount);

        // Charlie claims
        vm.prank(charlie);
        distributor.claim(epochId, charlieAmount, proofs[charlie]);
        assertEq(usdc.balanceOf(charlie), charlieAmount);

        // David claims
        vm.prank(david);
        distributor.claim(epochId, davidAmount, proofs[david]);
        assertEq(usdc.balanceOf(david), davidAmount);

        // Check all claimed
        assertTrue(distributor.hasClaimedForEpoch(epochId, alice));
        assertTrue(distributor.hasClaimedForEpoch(epochId, bob));
        assertTrue(distributor.hasClaimedForEpoch(epochId, charlie));
        assertTrue(distributor.hasClaimedForEpoch(epochId, david));

        // Check epoch claimed amount
        YieldDistributor.Epoch memory epoch = distributor.getEpoch(epochId);
        assertEq(epoch.claimedAmount, totalAmount);
    }

    function test_claim_revertsIfAlreadyClaimed() public {
        uint256 epochId = createTestEpoch();

        // Alice claims successfully
        vm.prank(alice);
        distributor.claim(epochId, aliceAmount, proofs[alice]);

        // Alice tries to claim again
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.AlreadyClaimed.selector);
        distributor.claim(epochId, aliceAmount, proofs[alice]);
    }

    function test_claim_revertsIfInvalidProof() public {
        uint256 epochId = createTestEpoch();

        // Alice tries to claim with Bob's proof
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.InvalidProof.selector);
        distributor.claim(epochId, aliceAmount, proofs[bob]);

        // Alice tries to claim with wrong amount
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.InvalidProof.selector);
        distributor.claim(epochId, bobAmount, proofs[alice]);
    }

    function test_claim_revertsIfEpochNotActive() public {
        uint256 epochId = createTestEpoch();

        // Cancel epoch
        vm.prank(owner);
        distributor.cancelEpoch(epochId);

        // Try to claim
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.EpochNotActive.selector);
        distributor.claim(epochId, aliceAmount, proofs[alice]);
    }

    function test_claim_revertsIfEpochNotStarted() public {
        fundDistributor(totalAmount);

        uint256 futureStart = block.timestamp + 1 days;

        vm.prank(owner);
        uint256 epochId = distributor.createEpoch(merkleRoot, totalAmount, address(usdc), futureStart, 0);

        // Try to claim before start time
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.EpochNotStarted.selector);
        distributor.claim(epochId, aliceAmount, proofs[alice]);

        // Warp to start time
        vm.warp(futureStart);

        // Now claim should work
        vm.prank(alice);
        distributor.claim(epochId, aliceAmount, proofs[alice]);
        assertEq(usdc.balanceOf(alice), aliceAmount);
    }

    function test_claim_revertsIfEpochExpired() public {
        uint256 expiryTime = block.timestamp + 30 days;
        uint256 epochId = createTestEpochWithExpiry(expiryTime);

        // Warp past expiry
        vm.warp(expiryTime + 1);

        // Try to claim
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.EpochExpired.selector);
        distributor.claim(epochId, aliceAmount, proofs[alice]);
    }

    function test_claim_revertsIfInvalidEpochId() public {
        vm.prank(alice);
        vm.expectRevert(YieldDistributor.InvalidEpochId.selector);
        distributor.claim(999, aliceAmount, proofs[alice]);
    }

    function test_claim_revertsIfZeroAmount() public {
        uint256 epochId = createTestEpoch();

        vm.prank(alice);
        vm.expectRevert(YieldDistributor.InvalidAmount.selector);
        distributor.claim(epochId, 0, proofs[alice]);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-CLAIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_claimMultiple() public {
        // Create two epochs
        uint256 epoch1 = createTestEpoch();

        fundDistributor(totalAmount);
        vm.prank(owner);
        uint256 epoch2 = distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, 0);

        // Alice claims from both epochs
        uint256[] memory epochIds = new uint256[](2);
        epochIds[0] = epoch1;
        epochIds[1] = epoch2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = aliceAmount;
        amounts[1] = aliceAmount;

        bytes32[][] memory multiProofs = new bytes32[][](2);
        multiProofs[0] = proofs[alice];
        multiProofs[1] = proofs[alice];

        vm.prank(alice);
        distributor.claimMultiple(epochIds, amounts, multiProofs);

        // Alice should have claimed from both epochs
        assertEq(usdc.balanceOf(alice), aliceAmount * 2);
        assertTrue(distributor.hasClaimedForEpoch(epoch1, alice));
        assertTrue(distributor.hasClaimedForEpoch(epoch2, alice));
    }

    function test_claimMultiple_revertsIfArrayLengthMismatch() public {
        uint256[] memory epochIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](2);
        bytes32[][] memory multiProofs = new bytes32[][](1);

        vm.prank(alice);
        vm.expectRevert("Array length mismatch");
        distributor.claimMultiple(epochIds, amounts, multiProofs);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL EPOCH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_cancelEpoch() public {
        uint256 epochId = createTestEpoch();

        vm.prank(owner);
        distributor.cancelEpoch(epochId);

        YieldDistributor.Epoch memory epoch = distributor.getEpoch(epochId);
        assertFalse(epoch.active);
    }

    function test_cancelEpoch_revertsIfNotOwner() public {
        uint256 epochId = createTestEpoch();

        vm.prank(alice);
        vm.expectRevert();
        distributor.cancelEpoch(epochId);
    }

    function test_cancelEpoch_revertsIfInvalidEpochId() public {
        vm.prank(owner);
        vm.expectRevert(YieldDistributor.InvalidEpochId.selector);
        distributor.cancelEpoch(999);
    }

    function test_cancelEpoch_revertsIfAlreadyInactive() public {
        uint256 epochId = createTestEpoch();

        vm.prank(owner);
        distributor.cancelEpoch(epochId);

        vm.prank(owner);
        vm.expectRevert(YieldDistributor.EpochNotActive.selector);
        distributor.cancelEpoch(epochId);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getEpoch() public {
        uint256 epochId = createTestEpoch();

        YieldDistributor.Epoch memory epoch = distributor.getEpoch(epochId);
        assertEq(epoch.merkleRoot, merkleRoot);
        assertEq(epoch.totalAmount, totalAmount);
        assertEq(epoch.asset, address(usdc));
        assertTrue(epoch.active);
    }

    function test_getEpoch_revertsIfInvalidEpochId() public {
        vm.expectRevert(YieldDistributor.InvalidEpochId.selector);
        distributor.getEpoch(999);
    }

    function test_getRemainingAmount() public {
        uint256 epochId = createTestEpoch();

        // Initially, all amount is remaining
        assertEq(distributor.getRemainingAmount(epochId), totalAmount);

        // Alice claims
        vm.prank(alice);
        distributor.claim(epochId, aliceAmount, proofs[alice]);

        // Remaining should be reduced
        assertEq(distributor.getRemainingAmount(epochId), totalAmount - aliceAmount);

        // Bob claims
        vm.prank(bob);
        distributor.claim(epochId, bobAmount, proofs[bob]);

        assertEq(distributor.getRemainingAmount(epochId), totalAmount - aliceAmount - bobAmount);
    }

    function test_verifyClaim() public {
        uint256 epochId = createTestEpoch();

        // Valid proof should verify
        assertTrue(distributor.verifyClaim(epochId, alice, aliceAmount, proofs[alice]));

        // Invalid proof should not verify
        assertFalse(distributor.verifyClaim(epochId, alice, aliceAmount, proofs[bob]));

        // Wrong amount should not verify
        assertFalse(distributor.verifyClaim(epochId, alice, bobAmount, proofs[alice]));

        // Invalid epoch should not verify
        assertFalse(distributor.verifyClaim(999, alice, aliceAmount, proofs[alice]));
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyWithdraw() public {
        fundDistributor(totalAmount);

        uint256 beforeBalance = usdc.balanceOf(owner);

        vm.prank(owner);
        distributor.emergencyWithdraw(address(usdc), totalAmount, owner);

        uint256 afterBalance = usdc.balanceOf(owner);
        assertEq(afterBalance - beforeBalance, totalAmount);
        assertEq(usdc.balanceOf(address(distributor)), 0);
    }

    function test_emergencyWithdraw_revertsIfNotOwner() public {
        fundDistributor(totalAmount);

        vm.prank(alice);
        vm.expectRevert();
        distributor.emergencyWithdraw(address(usdc), totalAmount, owner);
    }

    function test_emergencyWithdraw_revertsIfInvalidRecipient() public {
        fundDistributor(totalAmount);

        vm.prank(owner);
        vm.expectRevert("Invalid recipient");
        distributor.emergencyWithdraw(address(usdc), totalAmount, address(0));
    }

    function test_emergencyWithdraw_revertsIfInvalidAmount() public {
        fundDistributor(totalAmount);

        vm.prank(owner);
        vm.expectRevert("Invalid amount");
        distributor.emergencyWithdraw(address(usdc), 0, owner);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_fullDistributionFlow() public {
        // 1. Create epoch
        uint256 epochId = createTestEpoch();

        // 2. Verify initial state
        assertEq(distributor.getRemainingAmount(epochId), totalAmount);
        assertEq(usdc.balanceOf(address(distributor)), totalAmount);

        // 3. Contributors claim their allocations
        vm.prank(alice);
        distributor.claim(epochId, aliceAmount, proofs[alice]);

        vm.prank(bob);
        distributor.claim(epochId, bobAmount, proofs[bob]);

        vm.prank(charlie);
        distributor.claim(epochId, charlieAmount, proofs[charlie]);

        vm.prank(david);
        distributor.claim(epochId, davidAmount, proofs[david]);

        // 4. Verify final state
        assertEq(usdc.balanceOf(alice), aliceAmount);
        assertEq(usdc.balanceOf(bob), bobAmount);
        assertEq(usdc.balanceOf(charlie), charlieAmount);
        assertEq(usdc.balanceOf(david), davidAmount);

        assertEq(distributor.getRemainingAmount(epochId), 0);
        assertEq(usdc.balanceOf(address(distributor)), 0);

        YieldDistributor.Epoch memory epoch = distributor.getEpoch(epochId);
        assertEq(epoch.claimedAmount, totalAmount);
    }
}
