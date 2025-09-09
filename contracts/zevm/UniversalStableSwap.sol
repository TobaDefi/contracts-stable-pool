// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {SwapHelperLib} from "@zetachain/toolkit/contracts/SwapHelperLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniversalStableSwap is UniversalContract, Ownable {
    /// Represents the instance of the GatewayZEVM contract deployed on ZetaChain.
    IGatewayZEVM public immutable gateway;
    /// Represents the instance of the UniswapRouter contract deployed on ZetaChain.
    address public immutable uniswapRouter;
    /// Represents the instance of the Router contract deployed on ZetaChain.
    IRouter public immutable router;
    /// Represents the instance of the StablePoolKRW contract deployed on ZetaChain.
    address public immutable stablePool;
    /// Stores if token is whitelisted.
    mapping(address => bool) public isTokenWhitelisted;

    /// Structs
    struct CallParams {
        bytes receiver;
        address targetToken;
    }

    /// Errors
    error InvalidAddress();
    error Unauthorized();
    error ApproveFailed();

    /// Modifiers
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    constructor(
        address payable _gateway,
        address _uniswapRouter,
        address _router,
        address _stablePool
    ) Ownable(msg.sender) {
        if (_gateway == address(0) || _uniswapRouter == address(0) || _router == address(0) || _stablePool == address(0)) revert InvalidAddress();
        // Set the immutables.
        gateway = IGatewayZEVM(_gateway);
        uniswapRouter = _uniswapRouter;
        router = IRouter(_router);
        stablePool = _stablePool;
    }

    /// @notice Should whitelist the ZRC20 token address.
    /// @dev Callable only by owner.
    function whitelist(address token) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        isTokenWhitelisted[token] = true;
    }

    /// @notice Should handle cross-chain stables transfer.
    /// @dev should swap incoming ZRC20 to the output ZRC20 stable.
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message 
    ) external override onlyGateway {
        // Decode message to get the target token and receiver addresses.
        CallParams memory callParams = _decode(message);
        address targetToken = callParams.targetToken;
        
        // Check if tokens are whitelisted.
        if (!isTokenWhitelisted[zrc20] || !isTokenWhitelisted[targetToken]) revert InvalidAddress();
        // Swap stable in order to pay for gas fee.
        (address gasZRC20, uint256 gasFee) = IZRC20(targetToken).withdrawGasFee();
        uint256 inputForGas = SwapHelperLib.swapTokensForExactTokens(uniswapRouter, zrc20, gasFee, gasZRC20, amount);
        uint256 swapAmount = amount - inputForGas;
        
        // Swap input to the desired token using stable pool via router
        uint256 outputAmount = _swapViaStablePool(zrc20, targetToken, swapAmount);
        
        // Create token approvals.
        if (!IZRC20(gasZRC20).approve(address(gateway), gasFee)) revert ApproveFailed();
        if (!IZRC20(targetToken).approve(address(gateway), outputAmount)) revert ApproveFailed();
        
        // Create default revert options struct.
        RevertOptions memory revertOptions;
        
        // Initiate cross chain withdraw call.
        gateway.withdraw(callParams.receiver, outputAmount, targetToken, revertOptions);
    }

    /// @notice Swap tokens using the stable pool via router.
    /// @param tokenIn The input token address.
    /// @param tokenOut The output token address.
    /// @param amountIn The amount of input tokens.
    /// @return amountOut The amount of output tokens received.
    function _swapViaStablePool(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Approve the router to spend the input token.
        if (!IERC20(tokenIn).approve(address(router), amountIn)) revert ApproveFailed();
        
        uint256 deadline = block.timestamp + 1 hours;
        // Use the router's swapSingleTokenExactIn function to swap via stable pool.
        amountOut = router.swapSingleTokenExactIn(
            stablePool,
            IERC20(tokenIn),
            IERC20(tokenOut),
            amountIn,
            0, 
            deadline,
            false,
            "" 
        );
    }

    function _decode(
        bytes calldata message
    ) private pure returns (CallParams memory resp) {
        (resp.receiver, resp.targetToken) = abi.decode(message, (bytes, address));
    }
}