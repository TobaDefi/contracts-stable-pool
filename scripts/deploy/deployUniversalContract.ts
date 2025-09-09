import * as dotenv from "dotenv";
dotenv.config();

import hre from "hardhat";
import path from "path";
import { getAddressSaver, verify } from "./utils/helpers";
const { ethers, network } = hre;

const CONTRACT_NAME = "UniversalStableSwap";
const FILE_NAME = "deployment-contract-addrs";
const PATH_TO_FILE = path.join(__dirname, `./${FILE_NAME}.json`);

async function deploy() {
    const [deployer] = await ethers.getSigners();

    console.log("\n --- Deployed data --- \n");
    console.log("* ", deployer.address, "- Deployer address");
    console.log("* ", hre.network.name, "- Network name");
    console.log("* ", CONTRACT_NAME, "- Contract name");
    console.log("\n --- ------- ---- --- ");

    const Contract = await ethers.getContractFactory(CONTRACT_NAME);

    const gateway = '0x6c533f7fe93fae114d0954697069df33c9b74fd7';
    const uniswapRouter = '0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe';
    const router = '0xB4a9584e508E1dB7ebb8114573D39A69189CE1Ca';
    const stablePool = '0xA017203F31E817911D63820Ea81b1061AcE42FD5';
    const contract = await Contract.connect(deployer).deploy(gateway, uniswapRouter, router, stablePool);
    const deployTransaction = (await contract.deployed()).deployTransaction.wait();

    console.log(`Contract: \`${CONTRACT_NAME}\` is deployed to \`${contract.address}\`|\`${hre.network.name}\`.`);
    const saveAddress = getAddressSaver(PATH_TO_FILE, network.name, true);
    saveAddress(
        `${CONTRACT_NAME}`,
        {
            address: contract.address,
            deployedBlock: (await deployTransaction).blockNumber,
            chainId: ethers.provider.network.chainId
        },
        false
    );

    console.log(`\nDeployment the ${CONTRACT_NAME} is completed.`);
    await verify(contract.address, [gateway, uniswapRouter, router, stablePool]);

    console.log("\nDone.");
}

deploy().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
