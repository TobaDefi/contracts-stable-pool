import * as dotenv from "dotenv";
dotenv.config();

import hre from "hardhat";
import path from "path";
import { getAddressSaver, verify } from "./utils/helpers";
const { ethers, network } = hre;

import { TransactionReceipt } from "@ethersproject/abstract-provider";

import {
    VaultAdmin,
    VaultAdmin__factory,
    VaultExtension,
    VaultExtension__factory,
    ProtocolFeeController,
    ProtocolFeeController__factory,
    Vault,
    Vault__factory,
    StablePool,
    StablePool__factory
} from "../../typechain-types";

const CONTRACT_NAME = "StablePool";
const FILE_NAME = "deployment-balancer-contract-addrs";
const PATH_TO_FILE = path.join(__dirname, `./${FILE_NAME}.json`);

const DEFAULT_AMP_FACTOR = 200;

async function deploy() {
    const [deployer] = await ethers.getSigners();
    const provider = ethers.provider;
    const chainId = await provider.getNetwork().then((network) => network.chainId);

    console.log("\n --- Deployed data --- \n");
    console.log("* ", deployer.address, "- Deployer address");
    console.log("* ", hre.network.name, "- Network name");
    console.log("* ", CONTRACT_NAME, "- Contract names");
    console.log("\n --- ------- ---- --- ");

    const deployTxs: Promise<TransactionReceipt>[] = [];

    const stablePool = new StablePool__factory(deployer);
    const stablePoolContract: StablePool = await stablePool.connect(deployer).deploy(
        {
            name: "Universal KRW",
            symbol: "uKRW",
            amplificationParameter: DEFAULT_AMP_FACTOR,
            version: "1.0.0"
        },
        // vaultContract.address
        "0x1541CA9df8774D72Bc2f56DE44f5C019Cea4F180"
    );

    const deployTx = (await stablePoolContract.deployed()).deployTransaction.wait();
    const contractArgs = [
        { name: "Universal KRW", symbol: "uKRW", amplificationParameter: DEFAULT_AMP_FACTOR, version: "1.0.0" },
        // vaultContract.address
        "0x1541CA9df8774D72Bc2f56DE44f5C019Cea4F180"
    ];
    const contractAddress = stablePoolContract.address;
    console.log(`\n✅ Hash of TX #5: ${(await deployTx).transactionHash}\n`);

    const saveAddress = getAddressSaver(PATH_TO_FILE, network.name, true);
    const deployTransaction = await ethers.provider.getTransactionReceipt((await deployTx).transactionHash);
    saveAddress(
        CONTRACT_NAME,
        {
            address: contractAddress,
            deployedBlock: deployTransaction.blockNumber,
            chainId: chainId
        },
        false
    );

    // Verify contracts
    await verify(contractAddress, [...contractArgs]);

    console.log("Done. All contracts are deployed.");
}

deploy().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
