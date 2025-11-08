// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {YieldDistributor} from "../../distribution/YieldDistributor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}

contract YieldDistributorSetup is Test {
    YieldDistributor public distributor;
    MockERC20 public usdc;
    MockERC20 public dai;

    // Test addresses
    address public owner = address(1);
    address public alice = address(10);
    address public bob = address(11);
    address public charlie = address(12);
    address public david = address(13);

    // Test amounts (USDC has 6 decimals)
    uint256 public aliceAmount = 100 * 1e6; // 100 USDC
    uint256 public bobAmount = 200 * 1e6; // 200 USDC
    uint256 public charlieAmount = 150 * 1e6; // 150 USDC
    uint256 public davidAmount = 50 * 1e6; // 50 USDC

    uint256 public totalAmount;

    // Merkle tree data
    bytes32 public merkleRoot;
    bytes32[] public leaves;
    mapping(address => bytes32[]) public proofs;

    function setUp() public virtual {
        // Deploy contracts
        vm.startPrank(owner);
        distributor = new YieldDistributor(owner);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        vm.stopPrank();

        // Calculate total
        totalAmount = aliceAmount + bobAmount + charlieAmount + davidAmount;

        // Setup Merkle tree
        setupMerkleTree();

        // Label addresses for better traces
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
        vm.label(david, "david");
        vm.label(address(distributor), "distributor");
        vm.label(address(usdc), "usdc");
        vm.label(address(dai), "dai");
    }

    function setupMerkleTree() internal {
        // Create leaves (must match Solidity: keccak256(abi.encodePacked(address, uint256)))
        bytes32 aliceLeaf = keccak256(abi.encodePacked(alice, aliceAmount));
        bytes32 bobLeaf = keccak256(abi.encodePacked(bob, bobAmount));
        bytes32 charlieLeaf = keccak256(abi.encodePacked(charlie, charlieAmount));
        bytes32 davidLeaf = keccak256(abi.encodePacked(david, davidAmount));

        // Build Merkle tree manually for 4 leaves
        // Tree structure:
        //          root
        //         /    \
        //       h1      h2
        //      /  \    /  \
        //    L0  L1  L2  L3
        // Where L0=alice, L1=bob, L2=charlie, L3=david

        bytes32 h1 = _hashPair(aliceLeaf, bobLeaf);
        bytes32 h2 = _hashPair(charlieLeaf, davidLeaf);
        merkleRoot = _hashPair(h1, h2);

        // Generate proofs manually
        // Alice proof: [bobLeaf, h2]
        proofs[alice] = new bytes32[](2);
        proofs[alice][0] = bobLeaf;
        proofs[alice][1] = h2;

        // Bob proof: [aliceLeaf, h2]
        proofs[bob] = new bytes32[](2);
        proofs[bob][0] = aliceLeaf;
        proofs[bob][1] = h2;

        // Charlie proof: [davidLeaf, h1]
        proofs[charlie] = new bytes32[](2);
        proofs[charlie][0] = davidLeaf;
        proofs[charlie][1] = h1;

        // David proof: [charlieLeaf, h1]
        proofs[david] = new bytes32[](2);
        proofs[david][0] = charlieLeaf;
        proofs[david][1] = h1;
    }

    // Helper function to hash a pair of nodes (matches OpenZeppelin's MerkleProof sorting)
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function fundDistributor(uint256 amount) internal {
        vm.prank(owner);
        usdc.mint(address(distributor), amount);
    }

    function createTestEpoch() internal returns (uint256 epochId) {
        fundDistributor(totalAmount);

        vm.prank(owner);
        epochId = distributor.createEpoch(
            merkleRoot, totalAmount, address(usdc), block.timestamp, 0 // No expiry
        );
    }

    function createTestEpochWithExpiry(uint256 expiryTime) internal returns (uint256 epochId) {
        fundDistributor(totalAmount);

        vm.prank(owner);
        epochId = distributor.createEpoch(merkleRoot, totalAmount, address(usdc), block.timestamp, expiryTime);
    }
}
