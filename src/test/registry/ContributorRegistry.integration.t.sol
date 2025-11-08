// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../registry/ContributorRegistry.sol";

/**
 * @title ContributorRegistry Integration Test
 * @notice Integration tests using actual Merkle tree data from generate-merkle.ts
 *
 * Setup:
 * 1. Run: npm run generate-merkle (in scripts folder)
 * 2. Copy merkle root from data/merkle-root.txt
 * 3. Update MERKLE_ROOT constant below
 * 4. Copy proofs from data/proofs/*.json
 * 5. Update proof arrays below
 * 6. Run: forge test --match-contract IntegrationTest -vvv
 */
contract ContributorRegistryIntegrationTest is Test {
    ContributorRegistry public registry;

    // ⚠️ UPDATE THIS: Copy from data/merkle-root.txt after running npm run generate-merkle
    bytes32 constant MERKLE_ROOT = 0x66cf6e13520f475a680ae53236fde252f116b6e601dea9df7d31950f514136b4;

    // Test contributors (from contributors-test.json)
    address constant ALICE = 0x742d35Cc6634C0532925a3b844Bc454e4438f44e;
    address constant BOB = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    address constant CHARLIE = 0x1234567890123456789012345678901234567890;

    address owner = address(this);

    function setUp() public {
        // Skip if Merkle root not updated
        vm.assume(MERKLE_ROOT != bytes32(0));

        registry = new ContributorRegistry(MERKLE_ROOT, owner);
    }

    /*//////////////////////////////////////////////////////////////
                    INTEGRATION TESTS WITH REAL PROOFS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test Alice registration with real proof
     * @dev Update proof array with data from data/proofs/alice.json
     */
    function testIntegration_RegisterAlice() public {
        // ⚠️ UPDATE THIS: Copy proof from data/proofs/alice.json
        bytes32[] memory proof = new bytes32[](2);
        // proof[0] = 0x...; // First proof element
        // proof[1] = 0x...; // Second proof element
        proof[0] = 0x569114296f4ba921906bdcf19d9fac74e34819b28a31f82b213b9036e7dd782c;
        proof[1] = 0x966b28f8fe59e61a816c26390f41a2f7e2ceefd37149b5e01c669fd0a23bf59d;

        // Skip if proof not updated
        if (proof.length == 0 || proof[0] == bytes32(0)) {
            vm.skip(true);
        }

        string memory github = "alice";
        uint256 score = 54;

        // Verify proof works before registration
        bool isValidBefore = registry.verifyContributor(ALICE, github, score, proof);
        assertTrue(isValidBefore, "Proof should be valid");

        // Register
        vm.prank(ALICE);
        registry.register(github, score, proof);

        // Verify registration
        assertTrue(registry.isVerified(ALICE));

        ContributorRegistry.ContributorInfo memory info = registry.getContributor(ALICE);
        assertEq(info.github, github);
        assertEq(info.score, score);
        assertEq(info.votingPower, _sqrt(score));
    }

    /**
     * @notice Test Bob registration with real proof
     * @dev Update proof array with data from data/proofs/bob.json
     */
    function testIntegration_RegisterBob() public {
        // ⚠️ UPDATE THIS: Copy proof from data/proofs/bob.json
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0xe729e49a1f4eac456822669cbd86f92b238ee6cf34c5f3344c8c201a20e35fe5;
        // proof[1] = 0x...;

        if (proof.length == 0 || proof[0] == bytes32(0)) {
            vm.skip(true);
        }

        string memory github = "bob";
        uint256 score = 36;

        vm.prank(BOB);
        registry.register(github, score, proof);

        assertTrue(registry.isVerified(BOB));
    }

    /**
     * @notice Test multiple registrations
     */
    function testIntegration_MultipleRegistrations() public {
        // This test would register all three contributors
        // You would update it with real proofs from all three JSON files

        vm.skip(true); // Skip until proofs are updated
    }

    /**
     * @notice Test invalid proof rejection
     */
    function testIntegration_RejectInvalidProof() public {
        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = bytes32(uint256(12345));

        vm.prank(ALICE);
        vm.expectRevert(ContributorRegistry.InvalidProof.selector);
        registry.register("alice", 54, badProof);
    }

    /**
     * @notice Test wrong score rejection
     */
    function testIntegration_RejectWrongScore() public {
        // Use Alice's proof but wrong score
        bytes32[] memory proof = new bytes32[](2);
        // Copy Alice's proof here

        if (proof.length == 0 || proof[0] == bytes32(0)) {
            vm.skip(true);
        }

        uint256 wrongScore = 999; // Wrong score

        vm.prank(ALICE);
        vm.expectRevert(ContributorRegistry.InvalidProof.selector);
        registry.register("alice", wrongScore, proof);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /*//////////////////////////////////////////////////////////////
                    INSTRUCTIONS FOR UPDATING
    //////////////////////////////////////////////////////////////*/

    /**
     * HOW TO UPDATE THIS TEST WITH REAL PROOFS:
     *
     * 1. Generate Merkle tree:
     *    cd scripts
     *    npm run generate-merkle
     *
     * 2. Get Merkle root:
     *    cat ../data/merkle-root.txt
     *    Copy the value and update MERKLE_ROOT constant above
     *
     * 3. Get Alice's proof:
     *    cat ../data/proofs/alice.json
     *    Copy the "proof" array values
     *
     * 4. Update testIntegration_RegisterAlice():
     *    bytes32[] memory proof = new bytes32[](2); // Or however many elements in proof
     *    proof[0] = 0xabc123...; // First element from JSON
     *    proof[1] = 0xdef456...; // Second element from JSON
     *
     * 5. Repeat for Bob and Charlie
     *
     * 6. Run tests:
     *    forge test --match-contract IntegrationTest -vvv
     *
     * Example proof from alice.json:
     * {
     *   "proof": [
     *     "0xabc123...",
     *     "0xdef456..."
     *   ]
     * }
     *
     * Becomes:
     * proof[0] = 0xabc123...;
     * proof[1] = 0xdef456...;
     */
}
