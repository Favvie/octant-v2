#!/usr/bin/env node
/**
 * Generate Distribution Merkle Tree
 *
 * This script generates a Merkle tree for yield distribution
 * based on the allocation calculated in calculate-yield-distribution.ts
 */

import fs from 'fs';
import path from 'path';
import { ethers } from 'ethers';
import { MerkleTree } from 'merkletreejs';

interface ContributorAllocation {
  github: string;
  wallet: string;
  amount: string;
}

interface DistributionData {
  config: {
    epochId: number;
    asset: string;
    assetSymbol: string;
    decimals: number;
    totalYield: string;
    strategy: string;
    startTime: number;
    endTime: number;
  };
  allocations: ContributorAllocation[];
  totalAllocated: string;
  stats: any;
}

interface MerkleLeaf {
  wallet: string;
  github: string;
  amount: string;
  leaf: string;
  proof: string[];
}

interface MerkleOutput {
  epochId: number;
  root: string;
  totalLeaves: number;
  asset: string;
  assetSymbol: string;
  totalAmount: string;
  leaves: MerkleLeaf[];
}

/**
 * Create a Merkle leaf hash
 * Must match the Solidity implementation: keccak256(abi.encodePacked(wallet, amount))
 */
function createLeaf(wallet: string, amount: string): string {
  return ethers.solidityPackedKeccak256(
    ['address', 'uint256'],
    [wallet, amount]
  );
}

/**
 * Build Merkle tree from allocations
 */
function buildMerkleTree(allocations: ContributorAllocation[]): {
  tree: MerkleTree;
  leaves: string[];
} {
  // Sort by wallet address for deterministic tree
  const sorted = [...allocations].sort((a, b) =>
    a.wallet.toLowerCase().localeCompare(b.wallet.toLowerCase())
  );

  // Create leaves
  const leaves = sorted.map(allocation =>
    createLeaf(allocation.wallet, allocation.amount)
  );

  // Build tree
  const tree = new MerkleTree(leaves, ethers.keccak256, { sortPairs: true });

  return { tree, leaves };
}

/**
 * Main function
 */
async function main() {
  console.log('🌳 Generating Distribution Merkle Tree\n');

  // Get epoch ID from command line or use latest
  const epochId = process.argv[2] ? parseInt(process.argv[2]) : null;

  let distributionPath: string;

  if (epochId) {
    distributionPath = path.join(__dirname, `../data/distributions/epoch-${epochId}.json`);
  } else {
    // Find latest epoch
    const distributionsDir = path.join(__dirname, '../data/distributions');
    if (!fs.existsSync(distributionsDir)) {
      console.error('❌ No distributions found. Run calculate-yield-distribution.ts first');
      process.exit(1);
    }

    const files = fs.readdirSync(distributionsDir)
      .filter(f => f.startsWith('epoch-') && f.endsWith('.json'))
      .sort()
      .reverse();

    if (files.length === 0) {
      console.error('❌ No epoch files found. Run calculate-yield-distribution.ts first');
      process.exit(1);
    }

    distributionPath = path.join(distributionsDir, files[0]);
    console.log(`📂 Using latest epoch: ${files[0]}\n`);
  }

  if (!fs.existsSync(distributionPath)) {
    console.error('❌ Distribution file not found at:', distributionPath);
    process.exit(1);
  }

  // Load distribution data
  const distributionData: DistributionData = JSON.parse(fs.readFileSync(distributionPath, 'utf-8'));
  const { config, allocations } = distributionData;

  console.log('Configuration:');
  console.log(`  Epoch ID: ${config.epochId}`);
  console.log(`  Asset: ${config.assetSymbol}`);
  console.log(`  Total Contributors: ${allocations.length}`);
  console.log(`  Total Amount: ${ethers.formatUnits(config.totalYield, config.decimals)} ${config.assetSymbol}`);
  console.log('');

  // Build Merkle tree
  const { tree, leaves } = buildMerkleTree(allocations);
  const root = tree.getHexRoot();

  console.log('🌳 Merkle Tree Generated:');
  console.log(`  Root: ${root}`);
  console.log(`  Total Leaves: ${leaves.length}`);
  console.log('');

  // Sort allocations same way we sorted for tree building
  const sorted = [...allocations].sort((a, b) =>
    a.wallet.toLowerCase().localeCompare(b.wallet.toLowerCase())
  );

  // Generate proofs for each contributor
  const leavesWithProofs: MerkleLeaf[] = sorted.map((allocation, index) => {
    const leaf = leaves[index];
    const proof = tree.getHexProof(leaf);

    // Verify proof
    const verified = tree.verify(proof, leaf, root);
    if (!verified) {
      console.error(`❌ Proof verification failed for ${allocation.wallet}`);
      process.exit(1);
    }

    return {
      wallet: allocation.wallet,
      github: allocation.github,
      amount: allocation.amount,
      leaf,
      proof
    };
  });

  // Build output
  const output: MerkleOutput = {
    epochId: config.epochId,
    root,
    totalLeaves: leaves.length,
    asset: config.asset,
    assetSymbol: config.assetSymbol,
    totalAmount: distributionData.totalAllocated,
    leaves: leavesWithProofs
  };

  // Save complete tree
  const outputDir = path.join(__dirname, '../data/merkle-trees');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const merkleTreePath = path.join(outputDir, `epoch-${config.epochId}-merkle.json`);
  fs.writeFileSync(merkleTreePath, JSON.stringify(output, null, 2));

  // Save just the root for easy access
  const rootPath = path.join(outputDir, `epoch-${config.epochId}-root.txt`);
  fs.writeFileSync(rootPath, root);

  // Save individual proofs for easy lookup
  const proofsDir = path.join(outputDir, `epoch-${config.epochId}-proofs`);
  if (!fs.existsSync(proofsDir)) {
    fs.mkdirSync(proofsDir, { recursive: true });
  }

  leavesWithProofs.forEach(leaf => {
    const proofData = {
      wallet: leaf.wallet,
      github: leaf.github,
      amount: leaf.amount,
      amountFormatted: ethers.formatUnits(leaf.amount, config.decimals),
      assetSymbol: config.assetSymbol,
      proof: leaf.proof,
      leaf: leaf.leaf
    };

    const proofPath = path.join(proofsDir, `${leaf.github}.json`);
    fs.writeFileSync(proofPath, JSON.stringify(proofData, null, 2));
  });

  // Print sample proofs
  console.log('📋 Sample Proofs (first 3 contributors):');
  leavesWithProofs.slice(0, 3).forEach(leaf => {
    console.log(`\n  ${leaf.github} (${leaf.wallet}):`);
    console.log(`    Amount: ${ethers.formatUnits(leaf.amount, config.decimals)} ${config.assetSymbol}`);
    console.log(`    Proof Length: ${leaf.proof.length}`);
  });
  console.log('');

  console.log('✅ Files saved:');
  console.log(`  📄 Merkle tree: ${merkleTreePath}`);
  console.log(`  📄 Root: ${rootPath}`);
  console.log(`  📁 Individual proofs: ${proofsDir}/`);
  console.log('');
  console.log('🎯 Next steps:');
  console.log('  1. Fund the YieldDistributor contract with the asset tokens');
  console.log('  2. Call createEpoch() with the merkle root');
  console.log('  3. Share proof files with contributors for claiming');
}

main().catch(error => {
  console.error('❌ Error:', error);
  process.exit(1);
});
