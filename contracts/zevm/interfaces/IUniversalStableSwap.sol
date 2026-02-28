// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IUniversalStableSwapEvents
/// @notice Interface for the events emitted by the UniversalStableSwap contract.
interface IUniversalStableSwapEvents {
    /// @notice Emitted when a new ZRC20 token is whitelisted.
    /// @param token The address of the whitelisted ZRC20 token.
    event ZRC20TokenWhitelisted(address token);
}

/// @title IUniversalStableSwapErrors
/// @notice Interface for the errors used in the UniversalStableSwap contract.
interface IUniversalStableSwapErrors {
    /// @notice Error thrown when address is invalid.
    error InvalidAddress();
    /// @notice Error thrown when a function is called by an unauthorized address.
    error Unauthorized();
    /// @notice Error thrown when token approval fails.
    error ApproveFailed();
}

/// @title IUniversalStableSwap
/// @notice Interface for the UniversalStableSwap contract.
interface IUniversalStableSwap is IUniversalStableSwapErrors, IUniversalStableSwapEvents {}

/// @notice Params provided in the cross-chain stable swap call.
/// @param receiver The address of the receiver on the destination chain.
/// @param targetToken The ZRC20 token address of the target token.
struct StableSwapParams {
    bytes receiver;
    address targetToken;
}