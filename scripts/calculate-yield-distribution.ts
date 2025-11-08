#!/usr/bin/env node
/**
 * Calculate Yield Distribution
 *
 * This script calculates how much yield each contributor should receive
 * based on the allocation strategy (equal distribution or custom weights)
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { ethers } from 'ethers';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface ContributorAllocation {
  github: string;
  wallet: string;
  amount: string; // Amount in token decimals (e.g., USDC has 6 decimals)
}

interface DistributionConfig {
  epochId: number;
  asset: string; // Asset address (e.g., USDC)
  assetSymbol: string; // For display (e.g., "USDC")
  decimals: number; // Token decimals (e.g., 6 for USDC)
  totalYield: string; // Total yield available for distribution (in token decimals)
  strategy: 'equal' | 'custom';
  customWeights?: { [github: string]: number }; // Optional custom weights
  startTime: number; // Unix timestamp
  endTime: number; // Unix timestamp (0 for no expiry)
}

interface DistributionOutput {
  config: DistributionConfig;
  allocations: ContributorAllocation[];
  totalAllocated: string;
  stats: {
    totalContributors: number;
    avgAllocation: string;
    minAllocation: string;
    maxAllocation: string;
  };
}

/**
 * Load contributor data from GitHub tracker output
 */
function loadContributors(): any[] {
  const contributorsPath = path.join(__dirname, '../data/contributors.json');

  if (!fs.existsSync(contributorsPath)) {
    console.error('❌ Contributors file not found at:', contributorsPath);
    console.log('💡 Run: npm run track-github first');
    process.exit(1);
  }

  const data = JSON.parse(fs.readFileSync(contributorsPath, 'utf-8'));

  // Filter for eligible contributors (have wallet address)
  const eligible = data.contributors.filter((c: any) => c.eligible && c.wallet);

  if (eligible.length === 0) {
    console.error('❌ No eligible contributors found with wallet addresses');
    process.exit(1);
  }

  return eligible;
}

/**
 * Calculate equal distribution
 */
function calculateEqualDistribution(
  contributors: any[],
  totalYield: bigint
): Map<string, bigint> {
  const allocation = new Map<string, bigint>();
  const amountPerContributor = totalYield / BigInt(contributors.length);

  contributors.forEach(contributor => {
    allocation.set(contributor.wallet.toLowerCase(), amountPerContributor);
  });

  return allocation;
}

/**
 * Calculate custom weighted distribution
 */
function calculateCustomDistribution(
  contributors: any[],
  totalYield: bigint,
  customWeights: { [github: string]: number }
): Map<string, bigint> {
  const allocation = new Map<string, bigint>();

  // Calculate total weight
  let totalWeight = 0;
  const contributorWeights: { wallet: string; weight: number }[] = [];

  contributors.forEach(contributor => {
    const weight = customWeights[contributor.github] || 0;
    if (weight > 0) {
      totalWeight += weight;
      contributorWeights.push({
        wallet: contributor.wallet.toLowerCase(),
        weight
      });
    }
  });

  if (totalWeight === 0) {
    console.error('❌ Total weight is 0. No contributors have positive weights.');
    process.exit(1);
  }

  // Allocate proportionally
  contributorWeights.forEach(({ wallet, weight }) => {
    const amount = (totalYield * BigInt(Math.floor(weight * 1e18))) / BigInt(Math.floor(totalWeight * 1e18));
    allocation.set(wallet, amount);
  });

  return allocation;
}

/**
 * Main function
 */
async function main() {
  console.log('📊 Calculating Yield Distribution\n');

  // Load configuration
  const configPath = path.join(__dirname, '../data/distribution-config.json');

  if (!fs.existsSync(configPath)) {
    console.error('❌ Distribution config not found at:', configPath);
    console.log('💡 Create a distribution-config.json file with the following structure:');
    console.log(JSON.stringify({
      epochId: 1,
      asset: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      assetSymbol: 'USDC',
      decimals: 6,
      totalYield: '1000000000', // 1000 USDC (6 decimals)
      strategy: 'equal',
      startTime: Math.floor(Date.now() / 1000),
      endTime: 0
    }, null, 2));
    process.exit(1);
  }

  const config: DistributionConfig = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

  console.log('Configuration:');
  console.log(`  Epoch ID: ${config.epochId}`);
  console.log(`  Asset: ${config.assetSymbol} (${config.asset})`);
  console.log(`  Total Yield: ${ethers.formatUnits(config.totalYield, config.decimals)} ${config.assetSymbol}`);
  console.log(`  Strategy: ${config.strategy}`);
  console.log('');

  // Load contributors
  const contributors = loadContributors();
  console.log(`✅ Loaded ${contributors.length} eligible contributors\n`);

  // Calculate distribution
  const totalYield = BigInt(config.totalYield);
  let allocation: Map<string, bigint>;

  if (config.strategy === 'equal') {
    allocation = calculateEqualDistribution(contributors, totalYield);
  } else if (config.strategy === 'custom') {
    if (!config.customWeights) {
      console.error('❌ Custom strategy requires customWeights in config');
      process.exit(1);
    }
    allocation = calculateCustomDistribution(contributors, totalYield, config.customWeights);
  } else {
    console.error('❌ Invalid strategy. Must be "equal" or "custom"');
    process.exit(1);
  }

  // Build output
  const allocations: ContributorAllocation[] = [];
  let totalAllocated = 0n;
  const amounts: bigint[] = [];

  contributors.forEach(contributor => {
    const amount = allocation.get(contributor.wallet.toLowerCase());
    if (amount && amount > 0n) {
      allocations.push({
        github: contributor.github,
        wallet: contributor.wallet.toLowerCase(),
        amount: amount.toString()
      });
      totalAllocated += amount;
      amounts.push(amount);
    }
  });

  // Calculate stats
  const sortedAmounts = [...amounts].sort((a, b) => Number(a - b));
  const avgAllocation = totalAllocated / BigInt(allocations.length);

  const output: DistributionOutput = {
    config,
    allocations,
    totalAllocated: totalAllocated.toString(),
    stats: {
      totalContributors: allocations.length,
      avgAllocation: avgAllocation.toString(),
      minAllocation: sortedAmounts[0].toString(),
      maxAllocation: sortedAmounts[sortedAmounts.length - 1].toString()
    }
  };

  // Save output
  const outputDir = path.join(__dirname, '../data/distributions');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const outputPath = path.join(outputDir, `epoch-${config.epochId}.json`);
  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));

  console.log('📈 Distribution Summary:');
  console.log(`  Total Contributors: ${output.stats.totalContributors}`);
  console.log(`  Total Allocated: ${ethers.formatUnits(totalAllocated, config.decimals)} ${config.assetSymbol}`);
  console.log(`  Avg per Contributor: ${ethers.formatUnits(avgAllocation, config.decimals)} ${config.assetSymbol}`);
  console.log(`  Min Allocation: ${ethers.formatUnits(sortedAmounts[0], config.decimals)} ${config.assetSymbol}`);
  console.log(`  Max Allocation: ${ethers.formatUnits(sortedAmounts[sortedAmounts.length - 1], config.decimals)} ${config.assetSymbol}`);
  console.log('');
  console.log(`✅ Distribution saved to: ${outputPath}`);
}

main().catch(error => {
  console.error('❌ Error:', error);
  process.exit(1);
});