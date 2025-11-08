import { MerkleTree } from 'merkletreejs';
import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';

/**
 * MERKLE PROOF VERIFIER
 * 
 * Test script to verify individual Merkle proofs
 * Usage: npm run verify-proof -- --github=vitalik
 */

interface MerkleTreeData {
  root: string;
  totalLeaves: number;
  generatedAt: string;
  leaves: {
    github: string;
    wallet: string;
    score: number;
    leaf: string;
    proof: string[];
  }[];
}

/**
 * Verify a Merkle proof
 */
function verifyProof(
  proof: string[],
  root: string,
  leaf: string
): boolean {
  let computedHash = leaf;

  for (const proofElement of proof) {
    if (computedHash < proofElement) {
      // Hash(current, proofElement)
      computedHash = ethers.keccak256(
        ethers.concat([computedHash, proofElement])
      );
    } else {
      // Hash(proofElement, current)
      computedHash = ethers.keccak256(
        ethers.concat([proofElement, computedHash])
      );
    }
  }

  return computedHash === root;
}

/**
 * Get GitHub username from command line args
 */
function getGitHubFromArgs(): string | null {
  const args = process.argv.slice(2);
  const githubArg = args.find(arg => arg.startsWith('--github='));
  
  if (githubArg) {
    return githubArg.split('=')[1];
  }
  
  return null;
}

/**
 * Load Merkle tree data
 */
async function loadMerkleTreeData(): Promise<MerkleTreeData> {
  const filePath = path.join(process.cwd(), '../data/merkle-tree.json');
  const data = await fs.readFile(filePath, 'utf-8');
  return JSON.parse(data);
}

/**
 * Main function
 */
async function main() {
  console.log('🔍 MERKLE PROOF VERIFIER');
  console.log('='.repeat(60));

  // Get GitHub username from args
  const github = getGitHubFromArgs();

  if (!github) {
    console.log('\n❌ Please provide a GitHub username');
    console.log('\nUsage:');
    console.log('  npm run verify-proof -- --github=username');
    console.log('\nExample:');
    console.log('  npm run verify-proof -- --github=vitalik');
    return;
  }

  try {
    // Load Merkle tree data
    console.log('\n📂 Loading Merkle tree data...');
    const treeData = await loadMerkleTreeData();
    console.log(`  ✅ Loaded tree with ${treeData.totalLeaves} leaves`);
    console.log(`  🔑 Root: ${treeData.root}`);

    // Find contributor
    console.log(`\n🔎 Searching for contributor: ${github}`);
    const contributor = treeData.leaves.find(
      l => l.github.toLowerCase() === github.toLowerCase()
    );

    if (!contributor) {
      console.log(`  ❌ Contributor "${github}" not found in Merkle tree`);
      console.log('\n💡 Available contributors:');
      treeData.leaves.slice(0, 10).forEach(l => {
        console.log(`     - ${l.github} (score: ${l.score})`);
      });
      if (treeData.leaves.length > 10) {
        console.log(`     ... and ${treeData.leaves.length - 10} more`);
      }
      return;
    }

    console.log(`  ✅ Found contributor!`);
    console.log(`\n📋 CONTRIBUTOR INFO:`);
    console.log(`   GitHub: ${contributor.github}`);
    console.log(`   Wallet: ${contributor.wallet}`);
    console.log(`   Score: ${contributor.score}`);
    console.log(`   Leaf: ${contributor.leaf}`);

    // Verify proof
    console.log(`\n🔐 VERIFYING PROOF:`);
    console.log(`   Proof length: ${contributor.proof.length} hashes`);
    console.log(`   Root: ${treeData.root}`);

    const isValid = verifyProof(
      contributor.proof,
      treeData.root,
      contributor.leaf
    );

    if (isValid) {
      console.log(`\n✅ PROOF IS VALID!`);
      console.log(`\n   This contributor can successfully claim rewards on-chain.`);
    } else {
      console.log(`\n❌ PROOF IS INVALID!`);
      console.log(`\n   Something went wrong. The proof doesn't verify against the root.`);
    }

    // Display proof for copy-paste
    console.log(`\n📄 PROOF ARRAY (for smart contract):`);
    console.log(`[\n  "${contributor.proof.join('",\n  "')}"\n]`);

    // Generate Solidity test call
    console.log(`\n🔨 SOLIDITY VERIFICATION CALL:`);
    console.log(`verifyContributor(`);
    console.log(`  ${contributor.wallet},`);
    console.log(`  "${contributor.github}",`);
    console.log(`  ${contributor.score},`);
    console.log(`  [${contributor.proof.map(p => `\n    ${p}`).join(',')}`)
    console.log(`  ]`);
    console.log(`);`);

    // Show expected result
    console.log(`\n💡 Expected result: ${isValid}`);

  } catch (error: any) {
    if (error.code === 'ENOENT') {
      console.log('\n❌ Merkle tree file not found!');
      console.log('\n💡 Generate it first:');
      console.log('   npm run generate-merkle');
    } else {
      console.error('\n❌ Error:', error.message);
    }
  }
}

// Export for testing
export { verifyProof };

// Run the script
main().catch(console.error);