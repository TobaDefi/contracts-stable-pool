// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract StablePoolTest is BaseTest {
    function testSetUp() public view {
        // Verify all contracts are deployed correctly.
        assertTrue(address(router) != address(0), "Router not deployed");
        assertTrue(address(vault) != address(0), "Vault not deployed");
        assertTrue(address(vaultExtension) != address(0), "VaultExtension not deployed");
        assertTrue(address(vaultAdmin) != address(0), "VaultAdmin not deployed");
        assertTrue(address(protocolFeeController) != address(0), "ProtocolFeeController not deployed");
        assertTrue(address(stablePool) != address(0), "StablePool not deployed");
        
        // Verify test tokens are deployed.
        assertTrue(address(usdc) != address(0), "USDC not deployed");
        assertTrue(address(usdt) != address(0), "USDT not deployed");
        assertTrue(address(dai) != address(0), "DAI not deployed");
        assertTrue(address(weth) != address(0), "WETH not deployed");

        // TODO: check more info from VaultExtension contract.
        // Verify pool is registered and intialized.
        assertTrue(IVaultExtension(address(vault)).isPoolRegistered(address(stablePool)), "Pool not registered");
        assertTrue(IVaultExtension(address(vault)).isPoolInitialized(address(stablePool)), "Pool not initialized");

        // Verify initial balances.
        assertEq(usdc.balanceOf(user1), INITIAL_USER_BALANCE, "User1 USDC balance incorrect");
        assertEq(usdt.balanceOf(user1), INITIAL_USER_BALANCE, "User1 USDT balance incorrect");
        assertEq(dai.balanceOf(user1), INITIAL_USER_BALANCE, "User1 DAI balance incorrect");

    }
}