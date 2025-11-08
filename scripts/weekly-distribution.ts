#!/usr/bin/env node
/**
 * Weekly Yield Distribution Automation
 *
 * This script automates the complete weekly distribution workflow:
 * 1. Tracks GitHub contributions from the past week
 * 2. Calculates yield allocation per contributor
 * 3. Generates Merkle tree and proofs
 * 4. Prepares data for on-chain epoch creation
 *
 * Run this script every Monday (or your chosen distribution day)
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';
import { ethers } from 'ethers';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface WeeklyDistributionConfig {
  weekNumber: number;
  startDate: string;
  endDate: string;
  totalYieldWei: string;
  assetAddress: string;
  assetSymbol: string;
  decimals: number;
  allocationStrategy: 'equal' | 'proportional';
}

/**
 * Get the current week number (ISO week)
 */
function getCurrentWeekNumber(): number {
  const now = new Date();
  const start = new Date(now.getFullYear(), 0, 1);
  const diff = now.getTime() - start.getTime();
  const oneWeek = 1000 * 60 * 60 * 24 * 7;
  return Math.ceil(diff / oneWeek);
}

/**
 * Get date range for the past week
 */
function getWeekDateRange(): { start: string; end: string } {
  const now = new Date();
  const end = new Date(now);
  const start = new Date(now);
  start.setDate(start.getDate() - 7);

  return {
    start: start.toISOString().split('T')[0],
    end: end.toISOString().split('T')[0]
  };
}

/**
 * Query strategy contract for yield generated this week
 * This is a placeholder - you'll need to implement based on your RPC setup
 */
async function getWeeklyYield(
  strategyAddress: string,
  rpcUrl: string
): Promise<bigint> {
  console.log('📊 Querying strategy for weekly yield...');

  // TODO: Implement actual on-chain query
  // For now, this is a manual input
  const yieldInput = process.env.WEEKLY_YIELD_AMOUNT;

  if (!yieldInput) {
    console.error('❌ WEEKLY_YIELD_AMOUNT not set in environment');
    console.log('💡 Set it via: export WEEKLY_YIELD_AMOUNT="1000000000" (for 1000 USDC)');
    process.exit(1);
  }

  return BigInt(yieldInput);
}

/**
 * Track GitHub contributions for the past week
 */
async function trackGitHubContributions(): Promise<void> {
  console.log('🔍 Tracking GitHub contributions...\n');

  try {
    execSync('npm run track', {
      cwd: path.join(__dirname),
      stdio: 'inherit'
    });
  } catch (error) {
    console.error('❌ Failed to track GitHub contributions');
    throw error;
  }
}

/**
 * Create distribution config for this week
 */
function createDistributionConfig(
  weekNumber: number,
  totalYield: bigint,
  config: Partial<WeeklyDistributionConfig>
): void {
  const dateRange = getWeekDateRange();

  const distributionConfig = {
    epochId: weekNumber,
    asset: config.assetAddress || '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', // USDC mainnet
    assetSymbol: config.assetSymbol || 'USDC',
    decimals: config.decimals || 6,
    totalYield: totalYield.toString(),
    strategy: config.allocationStrategy || 'equal',
    startTime: Math.floor(Date.now() / 1000),
    endTime: 0, // No expiry
    metadata: {
      weekNumber,
      startDate: dateRange.start,
      endDate: dateRange.end,
      generatedAt: new Date().toISOString()
    }
  };

  const configPath = path.join(__dirname, '../data/distribution-config.json');
  fs.writeFileSync(configPath, JSON.stringify(distributionConfig, null, 2));

  console.log('✅ Distribution config created');
  console.log(`   Week: ${weekNumber}`);
  console.log(`   Period: ${dateRange.start} to ${dateRange.end}`);
  console.log(`   Total Yield: ${ethers.formatUnits(totalYield, distributionConfig.decimals)} ${distributionConfig.assetSymbol}`);
  console.log('');
}

/**
 * Calculate yield allocation for PaymentSplitter
 */
async function calculateAllocation(): Promise<void> {
  console.log('💰 Calculating PaymentSplitter allocation...\n');

  try {
    execSync('npm run calculate-payment-splitter', {
      cwd: path.join(__dirname),
      stdio: 'inherit'
    });
  } catch (error) {
    console.error('❌ Failed to calculate allocation');
    throw error;
  }
}

/**
 * Load distribution data for deployment
 */
function loadDistributionData(weekNumber: number): any {
  const dataPath = path.join(__dirname, `../data/distributions/week-${weekNumber}-payment-splitter.json`);

  if (!fs.existsSync(dataPath)) {
    throw new Error(`Distribution data not found at ${dataPath}`);
  }

  return JSON.parse(fs.readFileSync(dataPath, 'utf-8'));
}

/**
 * Generate deployment instructions for PaymentSplitter
 */
function generateDeploymentInstructions(
  weekNumber: number,
  totalYield: bigint,
  assetAddress: string,
  distributionData: any
): void {
  const { addresses, githubNames, shares } = distributionData.deployment;

  const instructions = `
╔════════════════════════════════════════════════════════════════╗
║    WEEK ${weekNumber} DISTRIBUTION - OCTANT PAYMENTSPLITTER        ║
╚════════════════════════════════════════════════════════════════╝

🎯 OCTANT INTEGRATION
This uses Octant's PaymentSplitter infrastructure:
- PaymentSplitterFactory for gas-efficient deployment
- YieldDonatingStrategy's dragonRouter integration
- Battle-tested PaymentSplitter contract

📋 DEPLOYMENT STEPS:

1️⃣  Approve WeeklyPaymentSplitterManager to spend dragonRouter shares:

   As dragonRouter owner:
   cast send $STRATEGY_ADDRESS \\
     "approve(address,uint256)" \\
     $WEEKLY_MANAGER_ADDRESS \\
     999999999999999999999999 \\
     --rpc-url $RPC_URL \\
     --private-key $DRAGON_ROUTER_KEY

2️⃣  Create weekly distribution (deploys PaymentSplitter + redeems shares):

   Arrays are in: data/distributions/week-${weekNumber}-payment-splitter.json

   cast send $WEEKLY_MANAGER_ADDRESS \\
     "createWeeklyDistribution(uint256,address[],string[],uint256[])" \\
     ${weekNumber} \\
     "[${addresses.map(a => `"${a}"`).join(',')}]" \\
     "[${githubNames.map(n => `"${n}"`).join(',')}]" \\
     "[${shares.join(',')}]" \\
     --rpc-url $RPC_URL \\
     --private-key $PRIVATE_KEY

   This will:
   - Redeem dragonRouter's ${totalYield.toString()} strategy shares
   - Deploy new PaymentSplitter via Octant's factory
   - Fund PaymentSplitter with redeemed assets
   - Record distribution in WeeklyPaymentSplitterManager

3️⃣  Get deployed PaymentSplitter address:

   cast call $WEEKLY_MANAGER_ADDRESS \\
     "getPaymentSplitter(uint256)" \\
     ${weekNumber} \\
     --rpc-url $RPC_URL

4️⃣  Notify contributors:

   Contributors can claim using Octant's PaymentSplitter:

   Example claim (as contributor):
   cast send $PAYMENT_SPLITTER_ADDRESS \\
     "release(address,address)" \\
     $ASSET_ADDRESS \\
     $CONTRIBUTOR_ADDRESS \\
     --rpc-url $RPC_URL \\
     --private-key $CONTRIBUTOR_KEY

5️⃣  Monitor claims:

   Check releasable amount for a contributor:
   cast call $PAYMENT_SPLITTER_ADDRESS \\
     "releasable(address,address)" \\
     $ASSET_ADDRESS \\
     $CONTRIBUTOR_ADDRESS \\
     --rpc-url $RPC_URL

═══════════════════════════════════════════════════════════════

📊 DISTRIBUTION SUMMARY:

Total Contributors: ${distributionData.stats.totalContributors}
Total Shares: ${distributionData.totalShares}
Total Yield: ${ethers.formatUnits(totalYield, distributionData.config.decimals)} ${distributionData.config.assetSymbol}

Top Contributors:
${distributionData.contributors.slice(0, 5).map((c: any, i: number) =>
  `${i + 1}. ${c.github.padEnd(20)} ${c.shares.toString().padStart(6)} shares (${c.percentage.toFixed(2)}%)`
).join('\n')}

═══════════════════════════════════════════════════════════════

📂 Generated Files:
   └─ data/distributions/week-${weekNumber}-payment-splitter.json

🎊 OCTANT FEATURES USED:
   ✅ PaymentSplitterFactory (gas-efficient proxy deployment)
   ✅ PaymentSplitter (pull payment model)
   ✅ YieldDonatingStrategy (dragonRouter integration)

═══════════════════════════════════════════════════════════════
`;

  console.log(instructions);

  // Save instructions to file
  const instructionsPath = path.join(__dirname, `../data/week-${weekNumber}-deployment.txt`);
  fs.writeFileSync(instructionsPath, instructions);
  console.log(`💾 Deployment instructions saved to: ${instructionsPath}\n`);
}

/**
 * Main function
 */
async function main() {
  console.log('╔════════════════════════════════════════════════════════╗');
  console.log('║     Weekly Yield Distribution - Automated Workflow    ║');
  console.log('╚════════════════════════════════════════════════════════╝\n');

  try {
    // Get configuration from environment
    const weekNumber = getCurrentWeekNumber();
    const strategyAddress = process.env.STRATEGY_ADDRESS || '';
    const rpcUrl = process.env.RPC_URL || '';
    const assetAddress = process.env.ASSET_ADDRESS || '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
    const assetSymbol = process.env.ASSET_SYMBOL || 'USDC';
    const decimals = parseInt(process.env.ASSET_DECIMALS || '6');
    const allocationStrategy = (process.env.ALLOCATION_STRATEGY || 'equal') as 'equal' | 'proportional';

    console.log(`📅 Week Number: ${weekNumber}`);
    console.log(`🏦 Asset: ${assetSymbol} (${assetAddress})`);
    console.log(`📊 Allocation Strategy: ${allocationStrategy}`);
    console.log('');

    // Step 1: Track GitHub contributions
    await trackGitHubContributions();

    // Step 2: Get weekly yield
    const totalYield = await getWeeklyYield(strategyAddress, rpcUrl);

    // Step 3: Create distribution config
    createDistributionConfig(weekNumber, totalYield, {
      assetAddress,
      assetSymbol,
      decimals,
      allocationStrategy
    });

    // Step 4: Calculate allocation for PaymentSplitter
    await calculateAllocation();

    // Step 5: Load distribution data
    const distributionData = loadDistributionData(weekNumber);

    // Step 6: Generate deployment instructions
    generateDeploymentInstructions(weekNumber, totalYield, assetAddress, distributionData);

    console.log('✅ Weekly distribution preparation complete!\n');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error during weekly distribution:', error);
    process.exit(1);
  }
}

// Run if called directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

export { main as runWeeklyDistribution };
