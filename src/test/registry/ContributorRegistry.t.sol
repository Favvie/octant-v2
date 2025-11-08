// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../registry/ContributorRegistry.sol";

contract ContributorRegistryTest is Test {
    ContributorRegistry public registry;

    // Test data matching the sample contributors from generate-merkle.ts
    address public alice = 0x742d35Cc6634C0532925a3b844Bc454e4438f44e;
    address public bob = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    address public charlie = 0x1234567890123456789012345678901234567890;
    address public owner = address(this);

    // Sample Merkle root (will be replaced with actual root from test data)
    bytes32 public merkleRoot;

    // Events to test
    event ContributorRegistered(address indexed wallet, string github, uint256 score, uint256 votingPower);

    event MerkleRootUpdated(bytes32 indexed oldRoot, bytes32 indexed newRoot);

    function setUp() public {
        // Generate test Merkle root
        // In practice, this would come from your generate-merkle.ts output
        merkleRoot = _generateTestMerkleRoot();

        // Deploy registry
        registry = new ContributorRegistry(merkleRoot, owner);
    }

    /*//////////////////////////////////////////////////////////////
                        REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Register_Success() public {
        string memory github = "alice";
        uint256 score = 54;
        bytes32[] memory proof = _getAliceProof();

        vm.prank(alice);

        vm.expectEmit(true, false, false, true);
        emit ContributorRegistered(alice, github, score, _sqrt(score));

        registry.register(github, score, proof);

        // Verify registration
        assertTrue(registry.isVerified(alice));

        ContributorRegistry.ContributorInfo memory info = registry.getContributor(alice);
        assertEq(info.github, github);
        assertEq(info.score, score);
        assertEq(info.votingPower, _sqrt(score));
        assertTrue(info.verified);

        assertEq(registry.totalRegistered(), 1);
    }

    function test_Register_RevertIf_AlreadyRegistered() public {
        string memory github = "alice";
        uint256 score = 54;
        bytes32[] memory proof = _getAliceProof();

        // Register once
        vm.prank(alice);
        registry.register(github, score, proof);

        // Try to register again
        vm.prank(alice);
        vm.expectRevert(ContributorRegistry.AlreadyRegistered.selector);
        registry.register(github, score, proof);
    }

    function test_Register_RevertIf_InvalidProof() public {
        string memory github = "alice";
        uint256 score = 54;
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(123));

        vm.prank(alice);
        vm.expectRevert(ContributorRegistry.InvalidProof.selector);
        registry.register(github, score, badProof);
    }

    function test_Register_RevertIf_WrongScore() public {
        string memory github = "alice";
        uint256 wrongScore = 999; // Wrong score
        bytes32[] memory proof = _getAliceProof();

        vm.prank(alice);
        vm.expectRevert(ContributorRegistry.InvalidProof.selector);
        registry.register(github, wrongScore, proof);
    }

    function test_Register_RevertIf_GithubAlreadyClaimed() public {
        string memory github = "alice";
        uint256 score = 54;
        bytes32[] memory proof = _getAliceProof();

        // Alice registers
        vm.prank(alice);
        registry.register(github, score, proof);

        // Bob tries to use Alice's GitHub
        vm.prank(bob);
        vm.expectRevert(ContributorRegistry.GithubAlreadyClaimed.selector);
        registry.register(github, score, proof);
    }

    function test_Register_RevertIf_EmptyGithub() public {
        string memory github = "";
        uint256 score = 54;
        bytes32[] memory proof = _getAliceProof();

        vm.prank(alice);
        vm.expectRevert(ContributorRegistry.InvalidGithub.selector);
        registry.register(github, score, proof);
    }

    function test_Register_RevertIf_ZeroScore() public {
        string memory github = "alice";
        uint256 score = 0;
        bytes32[] memory proof = _getAliceProof();

        vm.prank(alice);
        vm.expectRevert(ContributorRegistry.InvalidScore.selector);
        registry.register(github, score, proof);
    }

    function test_Register_MultipleContributors() public {
        // Register Alice
        vm.prank(alice);
        registry.register("alice", 54, _getAliceProof());

        // Register Bob
        vm.prank(bob);
        registry.register("bob", 36, _getBobProof());

        // Register Charlie
        vm.prank(charlie);
        registry.register("charlie", 23, _getCharlieProof());

        // Verify all registered
        assertTrue(registry.isVerified(alice));
        assertTrue(registry.isVerified(bob));
        assertTrue(registry.isVerified(charlie));
        assertEq(registry.totalRegistered(), 3);
    }

    /*//////////////////////////////////////////////////////////////
                        VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_VerifyContributor_ValidProof() public view {
        bool isValid = registry.verifyContributor(alice, "alice", 54, _getAliceProof());
        assertTrue(isValid);
    }

    function test_VerifyContributor_InvalidProof() public view {
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(123));

        bool isValid = registry.verifyContributor(alice, "alice", 54, badProof);
        assertFalse(isValid);
    }

    function test_IsVerified_NotRegistered() public view {
        assertFalse(registry.isVerified(alice));
    }

    function test_GetContributor_RevertIf_NotRegistered() public {
        vm.expectRevert(ContributorRegistry.NotRegistered.selector);
        registry.getContributor(alice);
    }

    function test_GetVotingPower() public {
        // Register Alice
        vm.prank(alice);
        registry.register("alice", 54, _getAliceProof());

        uint256 votingPower = registry.getVotingPower(alice);
        assertEq(votingPower, _sqrt(54));
    }

    function test_GetAddressForGithub() public {
        // Register Alice
        vm.prank(alice);
        registry.register("alice", 54, _getAliceProof());

        address addr = registry.getAddressForGithub("alice");
        assertEq(addr, alice);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateMerkleRoot() public {
        bytes32 newRoot = bytes32(uint256(999));

        vm.expectEmit(true, true, false, false);
        emit MerkleRootUpdated(merkleRoot, newRoot);

        registry.updateMerkleRoot(newRoot);
        assertEq(registry.merkleRoot(), newRoot);
    }

    function test_UpdateMerkleRoot_RevertIf_NotOwner() public {
        bytes32 newRoot = bytes32(uint256(999));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        registry.updateMerkleRoot(newRoot);
    }

    function test_BatchRegister_Success() public {
        address[] memory wallets = new address[](3);
        wallets[0] = alice;
        wallets[1] = bob;
        wallets[2] = charlie;

        string[] memory githubs = new string[](3);
        githubs[0] = "alice";
        githubs[1] = "bob";
        githubs[2] = "charlie";

        uint256[] memory scores = new uint256[](3);
        scores[0] = 54;
        scores[1] = 36;
        scores[2] = 23;

        bytes32[][] memory proofs = new bytes32[][](3);
        proofs[0] = _getAliceProof();
        proofs[1] = _getBobProof();
        proofs[2] = _getCharlieProof();

        registry.batchRegister(wallets, githubs, scores, proofs);

        assertEq(registry.totalRegistered(), 3);
        assertTrue(registry.isVerified(alice));
        assertTrue(registry.isVerified(bob));
        assertTrue(registry.isVerified(charlie));
    }

    function test_BatchRegister_RevertIf_NotOwner() public {
        address[] memory wallets = new address[](1);
        string[] memory githubs = new string[](1);
        uint256[] memory scores = new uint256[](1);
        bytes32[][] memory proofs = new bytes32[][](1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        registry.batchRegister(wallets, githubs, scores, proofs);
    }

    /*//////////////////////////////////////////////////////////////
                        VOTING POWER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_VotingPower_SquareRoot() public {
        // Test square root calculation
        assertEq(_sqrt(1), 1);
        assertEq(_sqrt(4), 2);
        assertEq(_sqrt(9), 3);
        assertEq(_sqrt(16), 4);
        assertEq(_sqrt(25), 5);
        assertEq(_sqrt(100), 10);
        assertEq(_sqrt(54), 7); // sqrt(54) ≈ 7.35 → 7
    }

    function test_VotingPower_QuadraticScaling() public {
        // Higher scores have diminishing voting power returns (quadratic scaling)
        // This demonstrates that voting power = sqrt(score)
        // Examples:
        // - Score 54 → voting power 7 (sqrt(54) ≈ 7.35 → 7)
        // - Score 100 → voting power 10 (sqrt(100) = 10)
        // - Score 400 → voting power 20 (sqrt(400) = 20)
        // Note: 4x score = 2x voting power (quadratic scaling)

        // Register Alice with score 54
        vm.prank(alice);
        registry.register("alice", 54, _getAliceProof());
        uint256 power54 = registry.getVotingPower(alice);
        assertEq(power54, 7); // sqrt(54) ≈ 7

        // Demonstrate quadratic scaling concept:
        // If someone had score 100, voting power would be sqrt(100) = 10
        // If someone had score 400, voting power would be sqrt(400) = 20
        // So 4x score only gives 2x voting power (diminishing returns)
        assertEq(_sqrt(54), 7);
        assertEq(_sqrt(100), 10);
        assertEq(_sqrt(400), 20);
        
        // Verify: 4x score (100 → 400) gives 2x power (10 → 20)
        // This is the quadratic scaling property
        assertTrue(_sqrt(400) == _sqrt(100) * 2);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Generate a test Merkle root
     * In real tests, import actual root from generate-merkle.ts output
     */
    function _generateTestMerkleRoot() internal pure returns (bytes32) {
        // Simple test root - in practice, use actual generated root
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = keccak256(
            abi.encodePacked(address(0x742d35Cc6634C0532925a3b844Bc454e4438f44e), "alice", uint256(54))
        );
        leaves[1] = keccak256(
            abi.encodePacked(address(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045), "bob", uint256(36))
        );
        leaves[2] = keccak256(
            abi.encodePacked(address(0x1234567890123456789012345678901234567890), "charlie", uint256(23))
        );

        // Simple Merkle tree calculation (for 3 leaves)
        bytes32 hash01 = _hashPair(leaves[0], leaves[1]);
        bytes32 root = _hashPair(hash01, leaves[2]);
        return root;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @dev Get Merkle proof for Alice
     * These would come from data/proofs/alice.json in real scenario
     */
    function _getAliceProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        // Simplified proof structure
        // In practice, copy exact proof from generate-merkle.ts output
        bytes32 bobLeaf = keccak256(
            abi.encodePacked(address(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045), "bob", uint256(36))
        );
        bytes32 charlieLeaf = keccak256(
            abi.encodePacked(address(0x1234567890123456789012345678901234567890), "charlie", uint256(23))
        );
        proof[0] = bobLeaf;
        proof[1] = charlieLeaf;
        return proof;
    }

    function _getBobProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](2);
        bytes32 aliceLeaf = keccak256(
            abi.encodePacked(address(0x742d35Cc6634C0532925a3b844Bc454e4438f44e), "alice", uint256(54))
        );
        bytes32 charlieLeaf = keccak256(
            abi.encodePacked(address(0x1234567890123456789012345678901234567890), "charlie", uint256(23))
        );
        proof[0] = aliceLeaf;
        proof[1] = charlieLeaf;
        return proof;
    }

    function _getCharlieProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](1);
        bytes32 aliceLeaf = keccak256(
            abi.encodePacked(address(0x742d35Cc6634C0532925a3b844Bc454e4438f44e), "alice", uint256(54))
        );
        bytes32 bobLeaf = keccak256(
            abi.encodePacked(address(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045), "bob", uint256(36))
        );
        proof[0] = _hashPair(aliceLeaf, bobLeaf);
        return proof;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
