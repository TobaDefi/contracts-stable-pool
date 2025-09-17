// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IUniversalDepositCoordinatorEvents
/// @notice Interface for the events emitted by the UniversalDepositCoordinator contract.
interface IUniversalDepositCoordinatorEvents {
    event DepositOrderCreated(
        uint256 indexed orderId,
        address indexed user,
        address indexed pool,
        uint256[] expectedAmounts,
        address[] expectedTokens,
        uint256 minBptAmountOut
    );
    
    event TokenReceived(
        uint256 indexed orderId,
        address indexed token,
        uint256 amount,
        uint256 remainingTokens
    );
    
    event DepositOrderExecuted(
        uint256 indexed orderId,
        address indexed user,
        uint256 bptAmountOut
    );
    
    event DepositOrderCancelled(
        uint256 indexed orderId,
        address indexed user,
        address[] returnedTokens,
        uint256[] returnedAmounts
    );
}

/// @title IUniversalDepositCoordinatorErrors
/// @notice Interface for the errors used in the UniversalDepositCoordinator contract.
interface IUniversalDepositCoordinatorErrors {
    error InvalidAddress();
    error Unauthorized();
    error OrderNotFound();
    error OrderAlreadyCompleted();
    error OrderNotReady();
    error InvalidTokenAmount();
    error InvalidTokenAddress();
    error InsufficientBptReceived();
    error OrderDeadlinePassed();
    error TokenAlreadyReceived();
    error InvalidOrderData();
}

/// @title IUniversalDepositCoordinator
/// @notice Interface for the UniversalDepositCoordinator contract.
interface IUniversalDepositCoordinator is IUniversalDepositCoordinatorErrors, IUniversalDepositCoordinatorEvents {}

/// @notice Represents a cross-chain deposit order for atomic liquidity provision.
struct DepositOrder {
    address user;                    
    address pool;                    
    uint256[] expectedAmounts;       
    address[] expectedTokens;        
    uint256[] receivedAmounts;       
    bool[] isReceived;              
    uint256 minBptAmountOut;        
    bool isCompleted;               
    uint256 orderId;                
}