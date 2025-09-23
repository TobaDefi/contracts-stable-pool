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

        // Verify pool is registered and intialized.
        assertTrue(IVaultExtension(address(vault)).isPoolRegistered(address(stablePool)), "Pool not registered");
        assertTrue(IVaultExtension(address(vault)).isPoolInitialized(address(stablePool)), "Pool not initialized");

        // Verify initial balances.
        assertEq(usdc.balanceOf(user1), INITIAL_USER_BALANCE, "User1 USDC balance incorrect");
        assertEq(usdt.balanceOf(user1), INITIAL_USER_BALANCE, "User1 USDT balance incorrect");
        assertEq(dai.balanceOf(user1), INITIAL_USER_BALANCE, "User1 DAI balance incorrect");

    }

    function testLiquidityProportional() public {
        uint256 exactBptAmountOut = 10e18;
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[0] = AMOUNT_IN; // USDC
        maxAmountsIn[1] = AMOUNT_IN; // USDT
        maxAmountsIn[2] = AMOUNT_IN; // DAI

        // Record balances before.
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);
        uint256 usdtBalanceBefore = usdt.balanceOf(user1);
        uint256 daiBalanceBefore = dai.balanceOf(user1);
        uint256 bptBalanceBefore = stablePool.balanceOf(user1);

        // Approve tokens.
        vm.startPrank(user1);
        usdc.approve(address(router), maxAmountsIn[0]);
        usdt.approve(address(router), maxAmountsIn[1]);
        dai.approve(address(router), maxAmountsIn[2]);

        // Add liquidity.
        uint256[] memory amountsIn = router.addLiquidityProportional(
            address(stablePool),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();

        // Verify amounts in are correct.
        assertTrue(amountsIn[0] > 0, "USDC amount in should be > 0");
        assertTrue(amountsIn[1] > 0, "USDT amount in should be > 0");
        assertTrue(amountsIn[2] > 0, "DAI amount in should be > 0");

        // Verify balances after.
        assertEq(usdc.balanceOf(user1), usdcBalanceBefore - amountsIn[0], "USDC balance incorrect");
        assertEq(usdt.balanceOf(user1), usdtBalanceBefore - amountsIn[1], "USDT balance incorrect");
        assertEq(dai.balanceOf(user1), daiBalanceBefore - amountsIn[2], "DAI balance incorrect");
        assertEq(stablePool.balanceOf(user1), bptBalanceBefore + exactBptAmountOut, "BPT balance incorrect");
    }

    function testAddLiquidityProportionalFailsIfPoolNotInitialized() public {
        uint256 exactBptAmountOut = 10e18;
        uint256[] memory maxAmountsIn = new uint256[](3);

        maxAmountsIn[0] = AMOUNT_IN;
        maxAmountsIn[1] = AMOUNT_IN;
        maxAmountsIn[2] = AMOUNT_IN;

        vm.startPrank(user1);
        usdc.approve(address(router), maxAmountsIn[0]);
        usdt.approve(address(router), maxAmountsIn[1]);
        dai.approve(address(router), maxAmountsIn[2]);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, address(0x123)));
        router.addLiquidityProportional(
            address(0x123),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testAddLiquidityProportionalFailsIfInsufficientAllowance() public {
        uint256 exactBptAmountOut = 10e18;
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[0] = AMOUNT_IN;
        maxAmountsIn[1] = AMOUNT_IN;
        maxAmountsIn[2] = AMOUNT_IN;

        vm.startPrank(user1);
        vm.expectRevert();
        router.addLiquidityProportional(
            address(stablePool),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testAddLiquidityProportionalFailsIfBptAmountOutBelowMin() public {
        uint256 exactBptAmountOut = 1000000e18;
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[0] = AMOUNT_IN;
        maxAmountsIn[1] = AMOUNT_IN;
        maxAmountsIn[2] = AMOUNT_IN;

        vm.startPrank(user1);
        usdc.approve(address(router), maxAmountsIn[0]);
        usdt.approve(address(router), maxAmountsIn[1]);
        dai.approve(address(router), maxAmountsIn[2]);

        vm.expectRevert();
        router.addLiquidityProportional(
            address(stablePool),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

     function testAddLiquidityUnbalanced() public {
        uint256[] memory exactAmountsIn = new uint256[](3);
        exactAmountsIn[0] = 100e6; // USDC
        exactAmountsIn[1] = 200e6; // USDT
        exactAmountsIn[2] = 300e6; // DAI
        uint256 minBptAmountOut = 5e18;

        // Record balances before.
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);
        uint256 usdtBalanceBefore = usdt.balanceOf(user1);
        uint256 daiBalanceBefore = dai.balanceOf(user1);
        uint256 bptBalanceBefore = stablePool.balanceOf(user1);

        // Approve tokens.
        vm.startPrank(user1);
        usdc.approve(address(router), exactAmountsIn[0]);
        usdt.approve(address(router), exactAmountsIn[1]);
        dai.approve(address(router), exactAmountsIn[2]);

        // Add liquidity.
        uint256 bptAmountOut = router.addLiquidityUnbalanced(
            address(stablePool),
            exactAmountsIn,
            minBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();

        // Verify BPT amount out.
        assertTrue(bptAmountOut >= minBptAmountOut, "BPT amount out should be >= min");

        // Verify balances after.
        assertEq(usdc.balanceOf(user1), usdcBalanceBefore - exactAmountsIn[0], "USDC balance incorrect");
        assertEq(usdt.balanceOf(user1), usdtBalanceBefore - exactAmountsIn[1], "USDT balance incorrect");
        assertEq(dai.balanceOf(user1), daiBalanceBefore - exactAmountsIn[2], "DAI balance incorrect");
        assertEq(stablePool.balanceOf(user1), bptBalanceBefore + bptAmountOut, "BPT balance incorrect");
    }

    function testAddLiquidityUnbalancedFailsIfInsufficientAllowance() public {
        uint256[] memory exactAmountsIn = new uint256[](3);
        exactAmountsIn[0] = 100e6;
        exactAmountsIn[1] = 200e6;
        exactAmountsIn[2] = 300e6;
        uint256 minBptAmountOut = 5e18;

        vm.startPrank(user1);
        vm.expectRevert();
        router.addLiquidityUnbalanced(
            address(stablePool),
            exactAmountsIn,
            minBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testAddLiquidityUnbalancedFailsIfExactAmountsInLengthMismatch() public {
        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = 100e6;
        exactAmountsIn[1] = 200e6;
        uint256 minBptAmountOut = 5e18;

        vm.startPrank(user1);
        usdc.approve(address(router), exactAmountsIn[0]);
        usdt.approve(address(router), exactAmountsIn[1]);

        vm.expectRevert();
        router.addLiquidityUnbalanced(
            address(stablePool),
            exactAmountsIn,
            minBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testAddLiquidityUnbalancedFailsIfMinBptAmountOutTooHigh() public {
        uint256[] memory exactAmountsIn = new uint256[](3);
        exactAmountsIn[0] = 1e6;
        exactAmountsIn[1] = 1e6;
        exactAmountsIn[2] = 1e6;
        uint256 minBptAmountOut = 1000e18;

        vm.startPrank(user1);
        usdc.approve(address(router), exactAmountsIn[0]);
        usdt.approve(address(router), exactAmountsIn[1]);
        dai.approve(address(router), exactAmountsIn[2]);

        vm.expectRevert();
        router.addLiquidityUnbalanced(
            address(stablePool),
            exactAmountsIn,
            minBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

    function testAddLiquiditySingleTokenExactOut() public {
        uint256 maxAmountIn = 1000e6;
        uint256 exactBptAmountOut = 5e18;

        // Record balances before.
        uint256 usdcBalanceBefore = usdc.balanceOf(user1);
        uint256 bptBalanceBefore = stablePool.balanceOf(user1);

        // Approve token.
        vm.startPrank(user1);
        usdc.approve(address(router), maxAmountIn);

        // Add liquidity.
        uint256 amountIn = router.addLiquiditySingleTokenExactOut(
            address(stablePool),
            usdc,
            maxAmountIn,
            exactBptAmountOut,
            false, // wethIsEth
            ""
        );
        vm.stopPrank();

        // Verify amount in.
        assertTrue(amountIn > 0, "Amount in should be > 0");
        assertTrue(amountIn <= maxAmountIn, "Amount in should be <= max");

        // Verify balances after.
        assertEq(usdc.balanceOf(user1), usdcBalanceBefore - amountIn, "USDC balance incorrect");
        assertEq(stablePool.balanceOf(user1), bptBalanceBefore + exactBptAmountOut, "BPT balance incorrect");
    }

    function testAddLiquiditySingleTokenExactOutFailsIfExactBptAmountOutIsZero() public {
        uint256 maxAmountIn = 1000e6;
        uint256 exactBptAmountOut = 0;

        vm.startPrank(user1);
        usdc.approve(address(router), maxAmountIn);

        vm.expectRevert();
        router.addLiquiditySingleTokenExactOut(
            address(stablePool),
            usdc,
            maxAmountIn,
            exactBptAmountOut,
            false,
            ""
        );
        vm.stopPrank();
    }

}