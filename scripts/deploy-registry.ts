import { ethers } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

const MERKLE_ROOT = '0x66cf6e13520f475a680ae53236fde252f116b6e601dea9df7d31950f514136b4';
const OWNER = '0xFDb60A0e05539aA30acba38813cF6123B8780b04';

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

  // Read registry contract bytecode
  const registryArtifactPath = path.join(process.cwd(), '..', 'out', 'ContributorRegistry.sol', 'ContributorRegistry.json');

  try {
    const registryArtifact = JSON.parse(await fs.readFile(registryArtifactPath, 'utf-8'));
    const registryFactory = new ethers.ContractFactory(registryArtifact.abi, registryArtifact.bytecode.object, signer);

    console.log('Deploying ContributorRegistry...');
    const registry = await registryFactory.deploy(MERKLE_ROOT, OWNER);

    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();

    console.log(`\n✓ ContributorRegistry deployed at: ${registryAddress}`);
    console.log(`\nAdd to .env:\nCONTRIBUTOR_REGISTRY_ADDRESS=${registryAddress}`);

  } catch (error) {
    console.error('Deployment failed:', error);
    process.exit(1);
  }
}

main();
