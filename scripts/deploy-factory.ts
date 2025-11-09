import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

const MANAGEMENT = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';
const KEEPER = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';
const EMERGENCY_ADMIN = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';

async function main() {
  const rpcUrl = process.env.ETH_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY;

  if (!rpcUrl || !privateKey) {
    throw new Error('Missing ETH_RPC_URL or PRIVATE_KEY in .env');
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(privateKey, provider);

  console.log('Deploying from:', signer.address);
  console.log('');

  // Read factory contract bytecode
  const factoryArtifactPath = path.join(process.cwd(), '..', 'out', 'YieldDonatingStrategyFactory.sol', 'YieldDonatingStrategyFactory.json');

  try {
    const factoryArtifact = JSON.parse(await fs.readFile(factoryArtifactPath, 'utf-8'));
    const factoryFactory = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode.object, signer);

    console.log('Deploying YieldDonatingStrategyFactory...');
    const factory = await factoryFactory.deploy(
      MANAGEMENT,
      MANAGEMENT,    // donationAddress (same as management for now)
      KEEPER,
      EMERGENCY_ADMIN
    );

    await factory.waitForDeployment();
    const factoryAddress = await factory.getAddress();

    console.log(`\n✓ Factory deployed at: ${factoryAddress}`);
    console.log(`\nAdd to .env:\nSTRATEGY_FACTORY_ADDRESS=${factoryAddress}`);

  } catch (error) {
    console.error('Deployment failed:', error);
    process.exit(1);
  }
}

main();
