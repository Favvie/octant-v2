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
import { execSync } from 'child_process';
import { ethers } from 'ethers';

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
 * Calculate yield allocation
 */
async function calculateAllocation(): Promise<void> {
  console.log('💰 Calculating yield allocation...\n');

  try {
    execSync('npm run calculate-distribution', {
      cwd: path.join(__dirname),
      stdio: 'inherit'
    });
  } catch (error) {
    console.error('❌ Failed to calculate allocation');
    throw error;
  }
}

/**
 * Generate Merkle tree and proofs
 */
async function generateMerkleTree(weekNumber: number): Promise<void> {
  console.log('🌳 Generating Merkle tree...\n');

  try {
    execSync(`npm run generate-distribution-merkle ${weekNumber}`, {
      cwd: path.join(__dirname),
      stdio: 'inherit'
    });
  } catch (error) {
    console.error('❌ Failed to generate Merkle tree');
    throw error;
  }
}

/**
 * Load Merkle root for on-chain deployment
 */
function loadMerkleRoot(weekNumber: number): string {
  const rootPath = path.join(__dirname, `../data/merkle-trees/epoch-${weekNumber}-root.txt`);

  if (!fs.existsSync(rootPath)) {
    throw new Error(`Merkle root not found at ${rootPath}`);
  }

  return fs.readFileSync(rootPath, 'utf-8').trim();
}

/**
 * Generate deployment instructions
 */
function generateDeploymentInstructions(
  weekNumber: number,
  totalYield: bigint,
  assetAddress: string,
  merkleRoot: string
): void {
  const instructions = `
╔════════════════════════════════════════════════════════════════╗
║           WEEK ${weekNumber} DISTRIBUTION - DEPLOYMENT READY           ║
╚════════════════════════════════════════════════════════════════╝

📋 NEXT STEPS:

1️⃣  Transfer yield to YieldDistributor contract:

   Amount: ${totalYield.toString()} (raw)
   Asset:  ${assetAddress}

   Example (using cast):
   cast send ${assetAddress} \\
     "transfer(address,uint256)" \\
     $YIELD_DISTRIBUTOR_ADDRESS \\
     ${totalYield.toString()} \\
     --rpc-url $RPC_URL \\
     --private-key $PRIVATE_KEY

2️⃣  Create epoch on YieldDistributor:

   Merkle Root: ${merkleRoot}
   Epoch ID:    ${weekNumber}

   Example (using cast):
   cast send $YIELD_DISTRIBUTOR_ADDRESS \\
     "createEpoch(bytes32,uint256,address,uint256,uint256)" \\
     ${merkleRoot} \\
     ${totalYield.toString()} \\
     ${assetAddress} \\
     $(date +%s) \\
     0 \\
     --rpc-url $RPC_URL \\
     --private-key $PRIVATE_KEY

3️⃣  Notify contributors:

   Proof files are in:
   data/merkle-trees/epoch-${weekNumber}-proofs/

   Share these files with contributors via:
   - IPFS
   - GitHub repository
   - Discord/Telegram bot
   - Email

4️⃣  Update frontend (if applicable):

   Add epoch ${weekNumber} to the UI with:
   - Merkle root: ${merkleRoot}
   - Total amount: ${totalYield.toString()}

═══════════════════════════════════════════════════════════════

📂 Generated Files:
   └─ data/distributions/epoch-${weekNumber}.json
   └─ data/merkle-trees/epoch-${weekNumber}-merkle.json
   └─ data/merkle-trees/epoch-${weekNumber}-root.txt
   └─ data/merkle-trees/epoch-${weekNumber}-proofs/*.json

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

    // Step 4: Calculate allocation
    await calculateAllocation();

    // Step 5: Generate Merkle tree
    await generateMerkleTree(weekNumber);

    // Step 6: Load Merkle root
    const merkleRoot = loadMerkleRoot(weekNumber);

    // Step 7: Generate deployment instructions
    generateDeploymentInstructions(weekNumber, totalYield, assetAddress, merkleRoot);

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
