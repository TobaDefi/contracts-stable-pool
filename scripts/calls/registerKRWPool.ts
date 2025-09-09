/* eslint-disable max-len */
import * as dotenv from "dotenv";
dotenv.config();

import hre from "hardhat";
const { ethers } = hre;

import { VaultExtension__factory } from "../../typechain-types";
import { AddressZero, Zero } from "../../test/helpers";

enum TokenType {
    STANDARD = 0,
    WITH_RATE = 1
}

// uKRW
const initializeKRWTokens = [
    "0x2Db395976CDb9eeFCc8920F4F2f0736f1D575794", // KBKRW.KAIROS
    "0xEb646191FcCb5Bfc1e7A121D3847590aAc840a53", // TSKRW.KAIROS
    "0xE8d7796535F1cd63F0fe8D631E68eACe6839869B", // HanaKRW.FUJI
    "0x0ca762FA958194795320635c11fF0C45C6412958" // UPKRW.ARBSEP
];

const chainIds = [
    1001, // KAIROS
    1001, // KAIROS
    43113, // FUJI
    421614 // ARBSEP
];

const sortedTokenAddresses = initializeKRWTokens.sort((a, b) => {
    return a.toLowerCase().localeCompare(b.toLowerCase());
});

console.log("Sorted token addresses:", sortedTokenAddresses);

const VAULT_TEST_ADDRESS = "0x1541CA9df8774D72Bc2f56DE44f5C019Cea4F180"; // ZetaChain Testnet Vault address
const STABLE_TEST_POOL_ADDRESS = "0xA017203F31E817911D63820Ea81b1061AcE42FD5"; // uKRW Stable Pool address on ZetaChain Testnet

async function main() {
    const [deployer] = await ethers.getSigners();
    const networkName = hre.network.name.toString();

    const vaultExtensionContract = VaultExtension__factory.connect(VAULT_TEST_ADDRESS, deployer);

    console.log("\n --- Register Pool Data --- \n");
    console.log("* ", deployer.address, "- Caller address");
    console.log("* ", networkName, "- Network name");
    console.log("* ", VAULT_TEST_ADDRESS, "- Contract address");
    console.log("\n --- ------- ---- --- ");

    const tokenConfigs = initializeKRWTokens.map((tokenAddress, index) => ({
        token: tokenAddress,
        chainId: chainIds[index],
        tokenType: TokenType.STANDARD,
        rateProvider: AddressZero,
        paysYieldFees: false
    }));

    const roleAccounts = {
        pauseManager: deployer.address,
        swapFeeManager: deployer.address,
        poolCreator: deployer.address
    };

    const liquidityManagement = {
        disableUnbalancedLiquidity: false,
        enableAddLiquidityCustom: false,
        enableRemoveLiquidityCustom: false,
        enableDonation: false
    };

    const registerPoolTx = await vaultExtensionContract.registerPool(
        STABLE_TEST_POOL_ADDRESS,
        tokenConfigs,
        1000000000000, // swapFeePercentage,
        Zero, // pauseWindowEndTime
        false, // protocolFeeExempt
        roleAccounts,
        AddressZero, // poolHooksContract
        liquidityManagement,
        {
            gasLimit: 5000000
        }
    );

    await registerPoolTx.wait();

    console.log(`\n✅ Hash of Pool Registration TX: ${registerPoolTx.hash}\n`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
