// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { ContributorQuadraticVoting } from "../../mechanisms/ContributorQuadraticVoting.sol";
import { TokenizedAllocationMechanism } from "../../../dependencies/octant-v2-core/src/mechanisms/TokenizedAllocationMechanism.sol";
import { AllocationConfig } from "../../../dependencies/octant-v2-core/src/mechanisms/BaseAllocationMechanism.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title ContributorQuadraticVoting Test
 * @notice Comprehensive tests for contributor-based quadratic voting mechanism
 */
contract ContributorQuadraticVotingTest is Test {
    ContributorQuadraticVoting public voting;
    TokenizedAllocationMechanism public implementation;
    ERC20Mock public asset;

    address public owner = address(0x1);
    address public keeper = address(0x2);
    address public management = address(0x3);

    // Test contributors
    address public alice = address(0x100);
    address public bob = address(0x101);
    address public charlie = address(0x102);

    // Merkle tree data (should be generated off-chain)
    bytes32 public merkleRoot;
    mapping(address => bytes32[]) public proofs;

    // Timing parameters
    uint256 public votingDelay = 1 days;
    uint256 public votingPeriod = 7 days;
    uint256 public timelockDelay = 2 days;
    uint256 public gracePeriod = 5 days;
    uint256 public quorumShares = 1000 * 1e18;

    function setUp() public {
        // Deploy mock ERC20 asset
        asset = new ERC20Mock();

        // Generate simple Merkle tree for testing
        // In production, use scripts/generate-merkle.ts
        _generateMerkleTree();

        // Deploy TokenizedAllocationMechanism implementation
        implementation = new TokenizedAllocationMechanism();

        // Configure allocation mechanism
        AllocationConfig memory config = AllocationConfig({
            asset: IERC20(address(asset)),
            name: "Contributor Allocation Shares",
            symbol: "CAS",
            votingDelay: votingDelay,
            votingPeriod: votingPeriod,
            quorumShares: quorumShares,
            timelockDelay: timelockDelay,
            gracePeriod: gracePeriod,
            owner: owner
        });

        // Deploy ContributorQuadraticVoting
        vm.prank(owner);
        voting = new ContributorQuadraticVoting(
            address(implementation),
            config,
            10000,  // alpha numerator (1.0 = full quadratic)
            10000,  // alpha denominator
            merkleRoot
        );

        // Set keeper and management
        vm.startPrank(owner);
        // Note: These would be set via the TokenizedAllocationMechanism
        // For testing, we'll mock the behavior
        vm.stopPrank();
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Generate a simple Merkle tree for testing
     * @dev In production, use off-chain scripts
     */
    function _generateMerkleTree() internal {
        // Create leaves for test contributors
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = keccak256(abi.encodePacked(alice, "alice", uint256(100)));
        leaves[1] = keccak256(abi.encodePacked(bob, "bob", uint256(400)));
        leaves[2] = keccak256(abi.encodePacked(charlie, "charlie", uint256(900)));

        // Calculate Merkle root (simplified - use MerkleTree library in production)
        // For now, we'll create a simple 3-leaf tree
        bytes32 hash01 = _hashPair(leaves[0], leaves[1]);
        merkleRoot = _hashPair(hash01, leaves[2]);

        // Generate proofs
        // Alice: [leaves[1], leaves[2]]
        proofs[alice] = new bytes32[](2);
        proofs[alice][0] = leaves[1];
        proofs[alice][1] = leaves[2];

        // Bob: [leaves[0], leaves[2]]
        proofs[bob] = new bytes32[](2);
        proofs[bob][0] = leaves[0];
        proofs[bob][1] = leaves[2];

        // Charlie: [hash01]
        proofs[charlie] = new bytes32[](1);
        proofs[charlie][0] = hash01;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ============================================
    // REGISTRATION TESTS
    // ============================================

    function test_RegisterContributor_Success() public {
        vm.prank(alice);
        voting.registerContributor("alice", 100, proofs[alice]);

        // Verify registration
        assertTrue(voting.isVerifiedContributor(alice));

        ContributorQuadraticVoting.ContributorInfo memory info = voting.getContributor(alice);
        assertEq(info.github, "alice");
        assertEq(info.score, 100);
        assertEq(info.votingPower, 10 * 1e18); // sqrt(100) = 10
        assertTrue(info.verified);
    }

    function test_RegisterContributor_RevertInvalidProof() public {
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(0);

        vm.prank(alice);
        vm.expectRevert(ContributorQuadraticVoting.InvalidMerkleProof.selector);
        voting.registerContributor("alice", 100, invalidProof);
    }

    function test_RegisterContributor_RevertAlreadyRegistered() public {
        vm.startPrank(alice);
        voting.registerContributor("alice", 100, proofs[alice]);

        vm.expectRevert(ContributorQuadraticVoting.AlreadyRegisteredAsContributor.selector);
        voting.registerContributor("alice", 100, proofs[alice]);
        vm.stopPrank();
    }

    function test_RegisterContributor_RevertGithubClaimed() public {
        vm.prank(alice);
        voting.registerContributor("alice", 100, proofs[alice]);

        // Try to register same GitHub with different address
        vm.prank(bob);
        vm.expectRevert(ContributorQuadraticVoting.GithubAlreadyClaimed.selector);
        voting.registerContributor("alice", 400, proofs[bob]);
    }

    function test_RegisterContributor_RevertInvalidGithub() public {
        vm.prank(alice);
        vm.expectRevert(ContributorQuadraticVoting.InvalidGithub.selector);
        voting.registerContributor("", 100, proofs[alice]);
    }

    function test_RegisterContributor_RevertInvalidScore() public {
        vm.prank(alice);
        vm.expectRevert(ContributorQuadraticVoting.InvalidScore.selector);
        voting.registerContributor("alice", 0, proofs[alice]);
    }

    // ============================================
    // VOTING POWER TESTS
    // ============================================

    function test_VotingPower_Calculation() public {
        // Test voting power for different scores
        vm.prank(alice);
        voting.registerContributor("alice", 100, proofs[alice]);

        vm.prank(bob);
        voting.registerContributor("bob", 400, proofs[bob]);

        vm.prank(charlie);
        voting.registerContributor("charlie", 900, proofs[charlie]);

        // Verify quadratic scaling
        ContributorQuadraticVoting.ContributorInfo memory aliceInfo = voting.getContributor(alice);
        ContributorQuadraticVoting.ContributorInfo memory bobInfo = voting.getContributor(bob);
        ContributorQuadraticVoting.ContributorInfo memory charlieInfo = voting.getContributor(charlie);

        assertEq(aliceInfo.votingPower, 10 * 1e18);  // sqrt(100) = 10
        assertEq(bobInfo.votingPower, 20 * 1e18);    // sqrt(400) = 20
        assertEq(charlieInfo.votingPower, 30 * 1e18); // sqrt(900) = 30

        // Verify quadratic property: 4x score = 2x voting power
        assertEq(bobInfo.votingPower, aliceInfo.votingPower * 2);
    }

    // ============================================
    // MERKLE PROOF TESTS
    // ============================================

    function test_VerifyContributor_ValidProof() public view {
        bool isValid = voting.verifyContributor(alice, "alice", 100, proofs[alice]);
        assertTrue(isValid);
    }

    function test_VerifyContributor_InvalidProof() public view {
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(0);

        bool isValid = voting.verifyContributor(alice, "alice", 100, invalidProof);
        assertFalse(isValid);
    }

    // ============================================
    // ADMIN TESTS
    // ============================================

    function test_UpdateMerkleRoot_Success() public {
        bytes32 newRoot = bytes32(uint256(123));

        vm.prank(owner);
        voting.updateMerkleRoot(newRoot);

        assertEq(voting.merkleRoot(), newRoot);
    }

    function test_UpdateMerkleRoot_RevertNotOwner() public {
        bytes32 newRoot = bytes32(uint256(123));

        vm.prank(alice);
        vm.expectRevert();
        voting.updateMerkleRoot(newRoot);
    }

    function test_UpdateMinPassportScore_Success() public {
        uint256 newScore = 20;

        vm.prank(owner);
        voting.updateMinPassportScore(newScore);

        assertEq(voting.minPassportScore(), newScore);
    }

    function test_UpdatePassportScorer_Success() public {
        address newScorer = address(0x999);

        vm.prank(owner);
        voting.updatePassportScorer(newScorer);

        assertEq(voting.passportScorer(), newScorer);
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_GetAddressForGithub() public {
        vm.prank(alice);
        voting.registerContributor("alice", 100, proofs[alice]);

        address addr = voting.getAddressForGithub("alice");
        assertEq(addr, alice);
    }

    function test_GetContributor_RevertNotVerified() public {
        vm.expectRevert(ContributorQuadraticVoting.NotAVerifiedContributor.selector);
        voting.getContributor(alice);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    /**
     * @notice Test complete workflow: register, propose, vote, finalize
     * @dev This is a simplified test - full integration tests would include
     *      actual proposal creation, voting, and share distribution
     */
    function test_IntegrationWorkflow_Placeholder() public {
        // TODO: Implement full integration tests
        // 1. Register contributors
        // 2. Create proposal
        // 3. Cast votes
        // 4. Finalize votes
        // 5. Queue proposal
        // 6. Redeem shares

        // For now, just test registration flow
        vm.prank(alice);
        voting.registerContributor("alice", 100, proofs[alice]);

        vm.prank(bob);
        voting.registerContributor("bob", 400, proofs[bob]);

        assertEq(voting.totalContributors(), 2);
    }
}
