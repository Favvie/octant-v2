import { MerkleTree } from 'merkletreejs';
import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';

/**
 * MERKLE TREE GENERATOR
 * 
 * Generates a Merkle tree from eligible contributors for gas-efficient
 * on-chain verification. Instead of storing all contributors on-chain,
 * we only store the Merkle root.
 */

// Types
interface Contributor {
  github: string;
  wallet: string | null;
  commits: number;
  prs: number;
  issues: number;
  reviews: number;
  totalScore: number;
  lastUpdated: string;
  eligible: boolean;
  repos: string[];
}

interface ContributorLeaf {
  github: string;
  wallet: string;
  score: number;
  leaf: string;
  proof: string[];
}

interface MerkleTreeOutput {
  root: string;
  totalLeaves: number;
  generatedAt: string;
  leaves: ContributorLeaf[];
  verificationInfo: {
    contractInterface: string;
    howToVerify: string;
  };
}

/**
 * Create a leaf hash for a contributor
 * 
 * Leaf = keccak256(abi.encodePacked(address, github, score))
 */
function createLeaf(wallet: string, github: string, score: number): string {
  // Encode the same way Solidity would: address + string + uint256
  // We use solidityPackedKeccak256 to match Solidity's abi.encodePacked + keccak256
  const leaf = ethers.solidityPackedKeccak256(
    ['address', 'string', 'uint256'],
    [wallet, github, score]
  );
  return leaf;
}

/**
 * Load contributors from JSON
 */
async function loadContributors(): Promise<Contributor[]> {
  const filePath = path.join(process.cwd(), '../data/contributors.json');
  const data = await fs.readFile(filePath, 'utf-8');
  const parsed = JSON.parse(data);
  return parsed.contributors || [];
}

/**
 * Filter eligible contributors
 */
function filterEligible(contributors: Contributor[]): Contributor[] {
  return contributors.filter(c => 
    c.eligible && 
    c.wallet !== null && 
    c.wallet !== '' &&
    ethers.isAddress(c.wallet)
  );
}

/**
 * Generate Merkle tree from contributors
 */
function generateMerkleTree(contributors: Contributor[]): {
  tree: MerkleTree;
  leaves: { contributor: Contributor; leaf: string }[];
} {
  console.log(`\n🌳 Generating Merkle tree for ${contributors.length} contributors...`);

  // Sort contributors by wallet address for deterministic tree
  const sorted = [...contributors].sort((a, b) => 
    a.wallet!.toLowerCase().localeCompare(b.wallet!.toLowerCase())
  );

  // Generate leaves
  const leaves = sorted.map(contributor => ({
    contributor,
    leaf: createLeaf(contributor.wallet!, contributor.github, contributor.totalScore)
  }));

  console.log(`  📄 Generated ${leaves.length} leaves`);

  // Create Merkle tree
  const leafHashes = leaves.map(l => l.leaf);
  const tree = new MerkleTree(leafHashes, ethers.keccak256, { 
    sortPairs: true,
    hashLeaves: false // Already hashed
  });

  console.log(`  🌲 Tree height: ${tree.getDepth()}`);
  console.log(`  🔑 Root: ${tree.getHexRoot()}`);

  return { tree, leaves };
}

/**
 * Generate proofs for all contributors
 */
function generateProofs(
  tree: MerkleTree,
  leaves: { contributor: Contributor; leaf: string }[]
): ContributorLeaf[] {
  console.log(`\n🔐 Generating Merkle proofs...`);

  const contributorLeaves: ContributorLeaf[] = leaves.map(({ contributor, leaf }) => {
    const proof = tree.getHexProof(leaf);
    
    return {
      github: contributor.github,
      wallet: contributor.wallet!,
      score: contributor.totalScore,
      leaf: leaf,
      proof: proof
    };
  });

  console.log(`  ✅ Generated ${contributorLeaves.length} proofs`);
  
  return contributorLeaves;
}

/**
 * Verify a proof (sanity check)
 */
function verifyProof(
  tree: MerkleTree,
  leaf: string,
  proof: string[]
): boolean {
  return tree.verify(proof, leaf, tree.getRoot());
}

/**
 * Generate verification info for smart contracts
 */
function generateVerificationInfo(root: string): string {
  return `
// SMART CONTRACT VERIFICATION

// 1. Store the Merkle root in your contract:
bytes32 public merkleRoot = ${root};

// 2. Verify a contributor's proof:
function verifyContributor(
    address wallet,
    string memory github,
    uint256 score,
    bytes32[] memory proof
) public view returns (bool) {
    bytes32 leaf = keccak256(abi.encodePacked(wallet, github, score));
    return MerkleProof.verify(proof, merkleRoot, leaf);
}

// 3. Example usage:
bool isValid = verifyContributor(
    0x742d35Cc6634C0532925a3b844Bc454e4438f44e,
    "vitalik",
    234,
    [0x123..., 0x456...] // proof array
);
`;
}

/**
 * Generate statistics
 */
function generateStats(
  allContributors: Contributor[],
  eligibleContributors: Contributor[]
) {
  const totalScore = eligibleContributors.reduce((sum, c) => sum + c.totalScore, 0);
  const avgScore = totalScore / eligibleContributors.length;
  
  console.log(`\n📊 STATISTICS:`);
  console.log(`   Total Contributors: ${allContributors.length}`);
  console.log(`   Eligible (with wallet): ${eligibleContributors.length}`);
  console.log(`   Not Eligible (no wallet): ${allContributors.length - eligibleContributors.length}`);
  console.log(`   Total Score: ${totalScore}`);
  console.log(`   Average Score: ${avgScore.toFixed(2)}`);
  console.log(`   Highest Score: ${Math.max(...eligibleContributors.map(c => c.totalScore))}`);
  console.log(`   Lowest Score: ${Math.min(...eligibleContributors.map(c => c.totalScore))}`);
}

/**
 * Save output files
 */
async function saveOutput(
  root: string,
  contributorLeaves: ContributorLeaf[],
  tree: MerkleTree
) {
  console.log(`\n💾 Saving output files...`);

  // 1. Save complete Merkle tree data
  const merkleTreeOutput: MerkleTreeOutput = {
    root: root,
    totalLeaves: contributorLeaves.length,
    generatedAt: new Date().toISOString(),
    leaves: contributorLeaves,
    verificationInfo: {
      contractInterface: 'See MERKLE_TREE_USAGE.md for smart contract examples',
      howToVerify: 'Use MerkleProof.verify(proof, root, leaf) in Solidity'
    }
  };

  const merkleTreePath = path.join(process.cwd(), '../data/merkle-tree.json');
  await fs.writeFile(merkleTreePath, JSON.stringify(merkleTreeOutput, null, 2));
  console.log(`  ✅ Saved: ${merkleTreePath}`);

  // 2. Save just the root (for easy contract deployment)
  const rootOnlyPath = path.join(process.cwd(), '../data/merkle-root.txt');
  await fs.writeFile(rootOnlyPath, root);
  console.log(`  ✅ Saved: ${rootOnlyPath}`);

  // 3. Save individual proof files (for easy lookup)
  const proofsDir = path.join(process.cwd(), '../data/proofs');
  try {
    await fs.mkdir(proofsDir, { recursive: true });
    
    for (const leaf of contributorLeaves) {
      const proofPath = path.join(proofsDir, `${leaf.github}.json`);
      await fs.writeFile(proofPath, JSON.stringify({
        github: leaf.github,
        wallet: leaf.wallet,
        score: leaf.score,
        leaf: leaf.leaf,
        proof: leaf.proof,
        root: root,
        howToUse: 'Pass proof array to smart contract verifyContributor() function'
      }, null, 2));
    }
    console.log(`  ✅ Saved ${contributorLeaves.length} individual proofs to: ${proofsDir}`);
  } catch (error) {
    console.error(`  ❌ Failed to save individual proofs:`, error);
  }

  // 4. Save tree structure (for debugging)
  const treeStructurePath = path.join(process.cwd(), '../data/merkle-tree-structure.txt');
  await fs.writeFile(treeStructurePath, tree.toString());
  console.log(`  ✅ Saved tree structure: ${treeStructurePath}`);
}

/**
 * Display sample proofs
 */
function displaySampleProofs(contributorLeaves: ContributorLeaf[], count: number = 3) {
  console.log(`\n📋 SAMPLE PROOFS (First ${count}):`);
  
  contributorLeaves.slice(0, count).forEach((leaf, i) => {
    console.log(`\n   ${i + 1}. ${leaf.github}`);
    console.log(`      Wallet: ${leaf.wallet}`);
    console.log(`      Score: ${leaf.score}`);
    console.log(`      Leaf: ${leaf.leaf}`);
    console.log(`      Proof Length: ${leaf.proof.length} hashes`);
    console.log(`      Proof: [`);
    leaf.proof.forEach((p, j) => {
      console.log(`        "${p}"${j < leaf.proof.length - 1 ? ',' : ''}`);
    });
    console.log(`      ]`);
  });
}

/**
 * Main function
 */
async function main() {
  console.log('🌳 MERKLE TREE GENERATOR');
  console.log('='.repeat(60));

  try {
    // 1. Load contributors
    console.log('\n📂 Loading contributors...');
    const allContributors = await loadContributors();
    console.log(`  ✅ Loaded ${allContributors.length} contributors`);

    // 2. Filter eligible
    const eligible = filterEligible(allContributors);
    console.log(`  ✅ Found ${eligible.length} eligible contributors`);

    if (eligible.length === 0) {
      console.log('\n⚠️  No eligible contributors found!');
      console.log('   Make sure contributors have:');
      console.log('   1. Score ≥ minimum score');
      console.log('   2. Valid wallet address in wallet-mappings.json');
      console.log('\n💡 Add wallet addresses to data/wallet-mappings.json');
      console.log('   Then re-run: npm run track');
      return;
    }

    // 3. Generate Merkle tree
    const { tree, leaves } = generateMerkleTree(eligible);
    const root = tree.getHexRoot();

    // 4. Generate proofs
    const contributorLeaves = generateProofs(tree, leaves);

    // 5. Verify all proofs (sanity check)
    console.log('\n🔍 Verifying all proofs...');
    let validCount = 0;
    let invalidCount = 0;

    for (const leaf of contributorLeaves) {
      const isValid = verifyProof(tree, leaf.leaf, leaf.proof);
      if (isValid) {
        validCount++;
      } else {
        invalidCount++;
        console.log(`  ❌ Invalid proof for ${leaf.github}`);
      }
    }

    console.log(`  ✅ Valid proofs: ${validCount}`);
    if (invalidCount > 0) {
      console.log(`  ❌ Invalid proofs: ${invalidCount}`);
      throw new Error('Some proofs are invalid!');
    }

    // 6. Generate statistics
    generateStats(allContributors, eligible);

    // 7. Display sample proofs
    displaySampleProofs(contributorLeaves);

    // 8. Save output
    await saveOutput(root, contributorLeaves, tree);

    // 9. Display verification info
    console.log(generateVerificationInfo(root));

    console.log('\n✅ Merkle tree generation complete!');
    console.log('\n📋 NEXT STEPS:');
    console.log('   1. Copy Merkle root to your smart contract');
    console.log('   2. Deploy ContributorRegistry contract');
    console.log('   3. Test proof verification with: npm run verify-proof');
    console.log('   4. Contributors can use their proofs to claim rewards');
    console.log(`\n📁 Output files:`);
    console.log(`   - data/merkle-tree.json (complete data)`);
    console.log(`   - data/merkle-root.txt (just the root)`);
    console.log(`   - data/proofs/{github}.json (individual proofs)`);
    console.log(`   - data/merkle-tree-structure.txt (tree visualization)`);

  } catch (error: any) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// Run the script
main().catch(console.error);