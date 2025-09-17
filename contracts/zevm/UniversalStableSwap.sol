// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/UniversalContract.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import "@zetachain/protocol-contracts/contracts/zevm/interfaces/IZRC20.sol";
import {SwapHelperLib} from "@zetachain/toolkit/contracts/SwapHelperLib.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IUniversalStableSwap, StableSwapParams} from "./interfaces/IUniversalStableSwap.sol";

/// @title UniversalStableSwap
/// @notice Helper contract that handles cross-chain stable swaps.
contract UniversalStableSwap is 
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IUniversalStableSwap,
    UniversalContract 
{
    /// Represents the instance of the GatewayZEVM contract deployed on ZetaChain.
    IGatewayZEVM public gateway;
    /// Represents the instance of the UniswapRouter contract deployed on ZetaChain.
    address public uniswapRouter;
    /// Represents the instance of the Router contract deployed on ZetaChain.
    IRouter public router;
    /// Represents the instance of the StablePoolKRW contract deployed on ZetaChain.
    address public stablePool;

    /// Stores if token is whitelisted.
    mapping(address => bool) public isTokenWhitelisted;

    /// Modifiers
    modifier onlyGateway() {
        if (msg.sender != address(gateway)) revert Unauthorized();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the UniversalStableSwap contract with required addresses and admin role.
    /// @param _gateway The ZetaChain Gateway contract address for cross-chain operations.
    /// @param _uniswapRouter The Uniswap router address for token swaps.
    /// @param _router The internal router contract address for stable pool operations.
    /// @param _stablePool The stable pool contract address for stable token swaps.
    /// @param _admin The admin address that will have DEFAULT_ADMIN_ROLE for contract management.
    function initialize(
        address payable _gateway,
        address _uniswapRouter,
        address _router,
        address _stablePool,
        address _admin
    ) public initializer {
        // Check the addresses.
        if (_gateway == address(0) || _uniswapRouter == address(0) || _router == address(0) || _stablePool == address(0) || _admin == address(0)) revert InvalidAddress();
        
        // Init Openzeppelin contracts.
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();

        // Grant roles.
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // Set the storage variables.
        gateway = IGatewayZEVM(_gateway);
        uniswapRouter = _uniswapRouter;
        router = IRouter(_router);
        stablePool = _stablePool;
    }

    /// @dev Authorizes the upgrade of the contract, sender must be owner.
    /// @param newImplementation Address of the new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @notice Should whitelist the ZRC20 token address.
    /// @dev Callable only by owner.
    function whitelist(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) revert InvalidAddress();
        isTokenWhitelisted[token] = true;
        emit ZRC20TokenWhitelisted(token);
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
        StableSwapParams memory callParams = _decode(message);
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
    ) private pure returns (StableSwapParams memory resp) {
        (resp.receiver, resp.targetToken) = abi.decode(message, (bytes, address));
    }
}