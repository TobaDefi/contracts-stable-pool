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
import {IUniversalDepositCoordinator, DepositOrder} from "./interfaces/IUniversalDepositCoordinator.sol";

/// @title UniversalDepositCoordinator
/// @notice Helper contract that handles cross-chain liquidity provision.
contract UniversalDepositCoordinator is 
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IUniversalDepositCoordinator,
    UniversalContract 
{
    /// Represents the instance of the GatewayZEVM contract deployed on ZetaChain.
    IGatewayZEVM public gateway;
    /// Represents the instance of the Router contract deployed on ZetaChain.
    IRouter public router;
    /// Represents the instance of the Vault contract deployed on ZetaChain.
    IVault public vault;
    /// @notice Next order ID counter.
    uint256 public nextOrderId;
     /// @notice Mapping of order ID to deposit order.
    mapping(uint256 => DepositOrder) public depositOrders;
    /// @notice Mapping of user address to their order IDs.
    mapping(address => uint256[]) public userOrders;
    /// @notice Mapping of user to token to pending amount for tracking.
    mapping(address => mapping(address => uint256)) public pendingDeposits;    
    /// @notice Mapping of ZRC20 tokens to pool tokens for validation.
    mapping(address => address) public zrc20ToPoolToken;

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
    /// @param _router The internal router contract address for stable pool operations.
    /// @param _vault The vault contract address for pool operations.
    /// @param _admin The admin address that will have DEFAULT_ADMIN_ROLE for contract management.
    function initialize(
        address payable _gateway,
        address _router,
        address _vault,
        address _admin
    ) public initializer {
        // Check the addresses.
        if (_gateway == address(0) || _router == address(0) || _vault == address(0) || _admin == address(0)) revert InvalidAddress();
        
        // Init Openzeppelin contracts.
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();

        // Grant roles.
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        // Set the storage variables.
        gateway = IGatewayZEVM(_gateway);
        router = IRouter(_router);
        vault = IVault(_vault);
    }

    /// @dev Authorizes the upgrade of the contract, sender must be owner.
    /// @param newImplementation Address of the new implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @notice Handles incoming ZRC20 tokens from cross-chain transfers.
    /// @dev Validates tokens against active deposit orders and updates order state.
    function onCall(
        MessageContext calldata context,
        address zrc20,
        uint256 amount,
        bytes calldata message 
    ) external override onlyGateway {
        if (amount == 0) return;

        // Decode orderId from message bytes.
        uint256 orderId = abi.decode(message, (uint256));
        
        // Validate order exists.
        if (orderId >= nextOrderId) {
            revert OrderNotFound();
        }

        DepositOrder storage order = depositOrders[orderId];
        
        // Validate order exists and is still active.
        if (order.user == address(0)) {
            revert OrderNotFound();
        }
        if (order.isCompleted) revert OrderAlreadyCompleted();

        // Find token index in order.
        uint256 tokenIndex = _findTokenIndexInOrder(order, zrc20);

        // Check if token already received.
        if (order.isReceived[tokenIndex]) revert TokenAlreadyReceived();

        // Validate amount matches expected.
        if (amount != order.expectedAmounts[tokenIndex]) revert InvalidTokenAmount();

        // Update order state.
        order.receivedAmounts[tokenIndex] = amount;
        order.isReceived[tokenIndex] = true;

        // Update pending deposits tracking.
        pendingDeposits[order.user][zrc20] += amount;

        // Calculate remaining tokens.
        uint256 remainingTokens = 0;
        for (uint256 i = 0; i < order.isReceived.length; i++) {
            if (!order.isReceived[i]) {
                remainingTokens++;
            }
        }

        emit TokenReceived(orderId, zrc20, amount, remainingTokens);
    }

    /// @notice Initiates a cross-chain deposit order for atomic liquidity provision.
    /// @param pool The target stable pool address.
    /// @param expectedAmounts Expected amounts for each token (in pool token order).
    /// @param expectedTokens Expected ZRC20 tokens (mapped to pool tokens).
    /// @param minBptAmountOut Minimum BPT amount to receive.
    /// @param deadline Order expiration timestamp.
    /// @return orderId The unique order identifier.
    function initiateDepositOrder(
        address pool,
        uint256[] calldata expectedAmounts,
        address[] calldata expectedTokens,
        uint256 minBptAmountOut
    ) external whenNotPaused nonReentrant returns (uint256 orderId) {
        // Validate inputs.
        if (pool == address(0)) revert InvalidAddress();
        if (expectedAmounts.length == 0 || expectedAmounts.length != expectedTokens.length) revert InvalidOrderData();
        if (minBptAmountOut == 0) revert InvalidTokenAmount();

        // Validate all expected amounts are positive.
        for (uint256 i = 0; i < expectedAmounts.length; i++) {
            if (expectedAmounts[i] == 0) revert InvalidTokenAmount();
            if (expectedTokens[i] == address(0)) revert InvalidTokenAddress();
        }

        // Generate order ID.
        orderId = nextOrderId++;

        // Create deposit order.
        DepositOrder storage order = depositOrders[orderId];
        order.user = msg.sender;
        order.pool = pool;
        order.expectedAmounts = expectedAmounts;
        order.expectedTokens = expectedTokens;
        order.receivedAmounts = new uint256[](expectedAmounts.length);
        order.isReceived = new bool[](expectedAmounts.length);
        order.minBptAmountOut = minBptAmountOut;
        order.orderId = orderId;

        // Add to user orders
        userOrders[msg.sender].push(orderId);

        emit DepositOrderCreated(
            orderId,
            msg.sender,
            pool,
            expectedAmounts,
            expectedTokens,
            minBptAmountOut
        );
    }

    /// @notice Executes a completed deposit order by adding liquidity to the pool
    /// @param orderId The order ID to execute
    /// @return bptAmountOut The actual BPT amount received
    function executeDepositOrder(uint256 orderId) external whenNotPaused nonReentrant returns (uint256 bptAmountOut) {
        DepositOrder storage order = depositOrders[orderId];
        
        // Validate order exists and is not completed
        if (order.user == address(0)) revert OrderNotFound();
        if (order.isCompleted) revert OrderAlreadyCompleted();
        if (block.timestamp > order.deadline) revert OrderExpired();

        // Validate all tokens have been received
        for (uint256 i = 0; i < order.isReceived.length; i++) {
            if (!order.isReceived[i]) revert OrderNotReady();
        }

        // Get pool tokens in correct order
        IERC20[] memory poolTokens = _getPoolTokens(order.pool);
        uint256[] memory amountsIn = new uint256[](poolTokens.length);

        // Prepare amounts for addLiquidityUnbalanced
        for (uint256 i = 0; i < order.expectedTokens.length; i++) {
            // Find corresponding pool token
            for (uint256 j = 0; j < poolTokens.length; j++) {
                if (zrc20ToPoolToken[order.expectedTokens[i]] == address(poolTokens[j])) {
                    amountsIn[j] = order.receivedAmounts[i];
                    break;
                }
            }
        }

        // Approve router to spend tokens
        for (uint256 i = 0; i < order.expectedTokens.length; i++) {
            IERC20(order.expectedTokens[i]).approve(address(router), order.receivedAmounts[i]);
        }

        // Add liquidity to pool
        bptAmountOut = router.addLiquidityUnbalanced(
            order.pool,
            amountsIn,
            order.minBptAmountOut,
            false, // wethIsEth
            "" // userData
        );

        // Validate minimum BPT received
        if (bptAmountOut < order.minBptAmountOut) revert InsufficientBptReceived();

        // Mark order as completed first
        order.isCompleted = true;

        // Clean up pending deposits
        for (uint256 i = 0; i < order.expectedTokens.length; i++) {
            pendingDeposits[order.user][order.expectedTokens[i]] -= order.receivedAmounts[i];
        }

        // Transfer BPT to order owner
        IERC20(order.pool).transfer(order.user, bptAmountOut);

        emit DepositOrderExecuted(orderId, order.user, bptAmountOut);
    }

    /// @notice Cancels an incomplete deposit order and returns received tokens
    /// @param orderId The order ID to cancel
    function cancelDepositOrder(uint256 orderId) external whenNotPaused nonReentrant {
        DepositOrder storage order = depositOrders[orderId];
        
        // Validate order exists and is not completed
        if (order.user == address(0)) revert OrderNotFound();
        if (order.isCompleted) revert OrderAlreadyCompleted();
        
        // Only order owner or admin can cancel
        if (msg.sender != order.user && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }

        // Return received tokens to order owner
        address[] memory returnedTokens = new address[](order.expectedTokens.length);
        uint256[] memory returnedAmounts = new uint256[](order.expectedTokens.length);
        uint256 returnCount = 0;

        // Mark order as completed first to prevent further execution
        order.isCompleted = true;

        for (uint256 i = 0; i < order.expectedTokens.length; i++) {
            if (order.isReceived[i]) {
                returnedTokens[returnCount] = order.expectedTokens[i];
                returnedAmounts[returnCount] = order.receivedAmounts[i];
                returnCount++;
                
                // Clean up pending deposits
                pendingDeposits[order.user][order.expectedTokens[i]] -= order.receivedAmounts[i];
            }
        }

        // Transfer tokens after state changes
        for (uint256 i = 0; i < order.expectedTokens.length; i++) {
            if (order.isReceived[i]) {
                IERC20(order.expectedTokens[i]).transfer(order.user, order.receivedAmounts[i]);
            }
        }

        emit DepositOrderCancelled(orderId, order.user, returnedTokens, returnedAmounts);
    }

    /// @notice Sets the mapping between ZRC20 tokens and pool tokens
    /// @param zrc20Token The ZRC20 token address
    /// @param poolToken The corresponding pool token address
    function setZrc20ToPoolTokenMapping(address zrc20Token, address poolToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (zrc20Token == address(0) || poolToken == address(0)) revert InvalidAddress();
        zrc20ToPoolToken[zrc20Token] = poolToken;
    }


    /// @notice Helper function to find token index in order
    function _findTokenIndexInOrder(DepositOrder storage order, address token) internal view returns (uint256) {
        for (uint256 i = 0; i < order.expectedTokens.length; i++) {
            if (order.expectedTokens[i] == token) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /// @notice Helper function to get pool tokens
    function _getPoolTokens(address pool) internal view returns (IERC20[] memory) {
        return vault.getPoolTokens(pool);
    }


}