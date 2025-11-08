#!/usr/bin/env node
/**
 * Calculate Payment Splitter Distribution
 *
 * This script calculates contributor shares for Octant's PaymentSplitter
 * (replaces Merkle-based distribution for hackathon Octant integration)
 */

import fs from 'fs';
import path from 'path';
import { ethers } from 'ethers';

interface ContributorShare {
  github: string;
  wallet: string;
  shares: number; // Proportional shares (not amount)
  percentage: number; // For display
}

interface PaymentSplitterConfig {
  epochId: number;
  totalYield: string;
  assetAddress: string;
  assetSymbol: string;
  decimals: number;
  strategy: 'equal' | 'proportional';
  customWeights?: { [github: string]: number };
}

interface PaymentSplitterOutput {
  config: PaymentSplitterConfig;
  contributors: ContributorShare[];
  totalShares: number;
  deployment: {
    addresses: string[];
    githubNames: string[];
    shares: number[];
  };
  stats: {
    totalContributors: number;
    estimatedAmountPerShare: string;
  };
}

/**
 * Load contributor data
 */
function loadContributors(): any[] {
  const contributorsPath = path.join(__dirname, '../data/contributors.json');

  if (!fs.existsSync(contributorsPath)) {
    console.error('❌ Contributors file not found at:', contributorsPath);
    console.log('💡 Run: npm run track first');
    process.exit(1);
  }

  const data = JSON.parse(fs.readFileSync(contributorsPath, 'utf-8'));
  const eligible = data.contributors.filter((c: any) => c.eligible && c.wallet);

  if (eligible.length === 0) {
    console.error('❌ No eligible contributors found with wallet addresses');
    process.exit(1);
  }

  return eligible;
}

/**
 * Calculate equal shares (everyone gets same number of shares)
 */
function calculateEqualShares(contributors: any[]): Map<string, number> {
  const shareMap = new Map<string, number>();
  const sharesPerPerson = 100; // Arbitrary number, ratio is what matters

  contributors.forEach(contributor => {
    shareMap.set(contributor.github, sharesPerPerson);
  });

  return shareMap;
}

/**
 * Calculate proportional shares based on contribution scores
 */
function calculateProportionalShares(
  contributors: any[],
  customWeights?: { [github: string]: number }
): Map<string, number> {
  const shareMap = new Map<string, number>();

  if (customWeights) {
    // Use custom weights
    Object.entries(customWeights).forEach(([github, weight]) => {
      shareMap.set(github, Math.floor(weight * 100)); // Scale to integers
    });
  } else {
    // Use contribution scores from GitHub tracker
    contributors.forEach(contributor => {
      const shares = Math.floor(contributor.totalScore); // Use score as shares
      shareMap.set(contributor.github, shares > 0 ? shares : 1); // Minimum 1 share
    });
  }

  return shareMap;
}

/**
 * Main function
 */
async function main() {
  console.log('📊 Calculating Payment Splitter Distribution\n');

  // Load configuration
  const configPath = path.join(__dirname, '../data/distribution-config.json');

  if (!fs.existsSync(configPath)) {
    console.error('❌ Distribution config not found at:', configPath);
    console.log('💡 Create a distribution-config.json file');
    process.exit(1);
  }

  const config: PaymentSplitterConfig = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

  console.log('Configuration:');
  console.log(`  Epoch ID: ${config.epochId}`);
  console.log(`  Asset: ${config.assetSymbol} (${config.assetAddress})`);
  console.log(`  Total Yield: ${ethers.formatUnits(config.totalYield, config.decimals)} ${config.assetSymbol}`);
  console.log(`  Strategy: ${config.strategy}`);
  console.log('');

  // Load contributors
  const contributors = loadContributors();
  console.log(`✅ Loaded ${contributors.length} eligible contributors\n`);

  // Calculate shares
  let shareMap: Map<string, number>;

  if (config.strategy === 'equal') {
    shareMap = calculateEqualShares(contributors);
  } else if (config.strategy === 'proportional') {
    shareMap = calculateProportionalShares(contributors, config.customWeights);
  } else {
    console.error('❌ Invalid strategy. Must be "equal" or "proportional"');
    process.exit(1);
  }

  // Calculate total shares
  let totalShares = 0;
  shareMap.forEach(shares => totalShares += shares);

  // Build output
  const contributorShares: ContributorShare[] = [];
  const addresses: string[] = [];
  const githubNames: string[] = [];
  const shares: number[] = [];

  contributors.forEach(contributor => {
    const contributorShares = shareMap.get(contributor.github) || 0;
    const percentage = (contributorShares / totalShares) * 100;

    contributorShares.push({
      github: contributor.github,
      wallet: contributor.wallet.toLowerCase(),
      shares: contributorShares,
      percentage
    });

    addresses.push(contributor.wallet.toLowerCase());
    githubNames.push(contributor.github);
    shares.push(contributorShares);
  });

  // Sort by shares descending
  contributorShares.sort((a, b) => b.shares - a.shares);

  // Calculate estimated amount per share
  const totalYield = BigInt(config.totalYield);
  const estimatedPerShare = totalYield / BigInt(totalShares);

  const output: PaymentSplitterOutput = {
    config,
    contributors: contributorShares,
    totalShares,
    deployment: {
      addresses,
      githubNames,
      shares
    },
    stats: {
      totalContributors: contributors.length,
      estimatedAmountPerShare: estimatedPerShare.toString()
    }
  };

  // Save output
  const outputDir = path.join(__dirname, '../data/distributions');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const outputPath = path.join(outputDir, `week-${config.epochId}-payment-splitter.json`);
  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));

  // Print summary
  console.log('📈 Distribution Summary:');
  console.log(`  Total Contributors: ${contributorShares.length}`);
  console.log(`  Total Shares: ${totalShares}`);
  console.log(`  Estimated per Share: ${ethers.formatUnits(estimatedPerShare, config.decimals)} ${config.assetSymbol}`);
  console.log('');

  console.log('🏆 Top 5 Contributors:');
  contributorShares.slice(0, 5).forEach((c, i) => {
    const estimatedAmount = (BigInt(c.shares) * totalYield) / BigInt(totalShares);
    console.log(`  ${i + 1}. ${c.github.padEnd(20)} ${c.shares.toString().padStart(6)} shares (${c.percentage.toFixed(2)}%) → ${ethers.formatUnits(estimatedAmount, config.decimals)} ${config.assetSymbol}`);
  });
  console.log('');

  console.log(`✅ Distribution data saved to: ${outputPath}`);
  console.log('');
  console.log('📋 Deployment Arrays (copy for contract call):');
  console.log('');
  console.log('addresses = [');
  addresses.forEach((addr, i) => {
    console.log(`  "${addr}"${i < addresses.length - 1 ? ',' : ''}`);
  });
  console.log(']');
  console.log('');
  console.log('githubNames = [');
  githubNames.forEach((name, i) => {
    console.log(`  "${name}"${i < githubNames.length - 1 ? ',' : ''}`);
  });
  console.log(']');
  console.log('');
  console.log('shares = [');
  shares.forEach((share, i) => {
    console.log(`  ${share}${i < shares.length - 1 ? ',' : ''}`);
  });
  console.log(']');
}

main().catch(error => {
  console.error('❌ Error:', error);
  process.exit(1);
});
