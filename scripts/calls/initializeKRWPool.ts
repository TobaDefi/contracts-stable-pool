/* eslint-disable max-len */
import * as dotenv from "dotenv";
dotenv.config();

import hre from "hardhat";

const { ethers } = hre;
const { parseUnits } = ethers.utils;
import { Router__factory, TestToken__factory } from "../../typechain-types";

const initializeKRWTokens = [
    "0x0ca762FA958194795320635c11fF0C45C6412958", // UPKRW.ARBSEP
    "0x2Db395976CDb9eeFCc8920F4F2f0736f1D575794", // KBKRW.KAIROS
    "0xE8d7796535F1cd63F0fe8D631E68eACe6839869B", // HanaKRW.FUJI
    "0xEb646191FcCb5Bfc1e7A121D3847590aAc840a53" // TSKRW.KAIROS
];

const ROUTER_TEST_ADDRESS = "0xB4a9584e508E1dB7ebb8114573D39A69189CE1Ca"; // ZetaChain Testnet Router address
const STABLE_TEST_POOL_ADDRESS = "0xA017203F31E817911D63820Ea81b1061AcE42FD5"; // uKRW Stable Pool address on ZetaChain Testnet

async function main() {
    const [caller] = await ethers.getSigners();
    const networkName = hre.network.name.toString();

    const routerContract = Router__factory.connect(ROUTER_TEST_ADDRESS, caller);

    console.log("\n --- Initialize Pool on Router --- \n");
    console.log("* ", caller.address, "- Caller address");
    console.log("* ", networkName, "- Network name");
    console.log("* ", ROUTER_TEST_ADDRESS, "- Contract address");
    console.log("\n --- ------- ---- --- ");

    const initializeAmount = "10000";
    const initializeAmounts = [];

    // Approve tokens for the router
    for (const tokenAddress of initializeKRWTokens) {
        const tokenContract = TestToken__factory.connect(tokenAddress, caller);
        const decimals = await tokenContract.decimals();
        const amount = parseUnits(initializeAmount, decimals);
        const allowance = await tokenContract.allowance(caller.address, ROUTER_TEST_ADDRESS);
        if (allowance.lt(amount)) {
            const approvalTx = await tokenContract.approve(ROUTER_TEST_ADDRESS, amount);
            await approvalTx.wait();
            console.log(`Approved ${tokenAddress} tokens for the router.`);
        }
        initializeAmounts.push(amount);
    }

    const initializePoolTx = await routerContract.initialize(
        STABLE_TEST_POOL_ADDRESS,
        initializeKRWTokens,
        initializeAmounts,
        parseUnits("0", 18), // min Bpt AmountOut
        false, // weth is eth
        "0x" // No additional user data
    );

    await initializePoolTx.wait();

    console.log(`\n✅ Hash of Pool Initialization TX: ${initializePoolTx.hash}\n`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
