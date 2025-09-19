// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std-1.10.0/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGatewayZEVM} from "@zetachain/protocol-contracts/contracts/zevm/interfaces/IGatewayZEVM.sol";
import {IWETH} from "../../contracts/interfaces/IWETH.sol";
import {Vault} from "../../contracts/Vault.sol";
import {VaultExtension} from "../../contracts/VaultExtension.sol";
import {VaultAdmin} from "../../contracts/VaultAdmin.sol";
import {ProtocolFeeController} from "../../contracts/ProtocolFeeController.sol";
import {Router} from "../../contracts/Router.sol";
import {StablePool} from "../../contracts/StablePool.sol";
import {StablePoolFactory} from "../../contracts/common/StablePoolFactory.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {IVaultAdmin} from "../../contracts/interfaces/IVaultAdmin.sol";
import {IVaultExtension} from "../../contracts/interfaces/IVaultExtension.sol";
import {IStablePool} from "../../contracts/interfaces/IStablePool.sol";
import {IRateProvider} from "../../contracts/interfaces/IRateProvider.sol";
import {IAuthorizer} from "../../contracts/interfaces/IAuthorizer.sol";
import {IVaultErrors} from "../../contracts/interfaces/IVaultErrors.sol";
import {IProtocolFeeController} from "../../contracts/interfaces/IProtocolFeeController.sol";
import {TokenConfig, PoolRoleAccounts, LiquidityManagement, TokenType} from "../../contracts/common/VaultTypes.sol";
import {MockERC20} from "../../contracts/mocks/MockERC20.sol";
import {MockWETH9} from "../../contracts/mocks/MockWETH9.sol";

abstract contract BaseTest is Test {
    // Core contracts.
    Router public router;
    Vault public vault;
    VaultExtension public vaultExtension;
    VaultAdmin public vaultAdmin;
    ProtocolFeeController public protocolFeeController;
    StablePool public stablePool;
    StablePoolFactory public stablePoolFactory;

    IGatewayZEVM public GATEWAY = IGatewayZEVM(address(0x99));
    address public UNISWAP_ROUTER = address(0x88);

    // Test tokens.
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public dai;
    MockWETH9 public weth;
    uint256 public constant AMOUNT_TO_MINT = 1000000e6;
    
    // Test accounts.
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    // Pool parameters.
    uint32 public constant PAUSE_WINDOW_DURATION = 90 days;
    uint32 public constant BUFFER_PERIOD_DURATION = 30 days;
    uint256 public constant MINIMUM_TRADE_AMOUNT = 1e6;
    uint256 public constant MINIMUM_WRAP_AMOUNT = 1e3;
    uint256 public constant DEFAULT_AMP_FACTOR = 200;
    uint256 public constant SWAP_FEE_PERCENTAGE = 1000000000000; 
    uint256 public constant MIN_BPT_AMOUNT_OUT = 5e18; 
    uint256 public constant INITIAL_LIQUIDITY = 100e6;
    uint256 public constant AMOUNT_IN = 100e6;
    uint256 public constant INITIAL_USER_BALANCE = 10000e6; 
    
    uint256 public CHAIN_ID;
    uint256 public constant ZERO = 0;
    address public constant ZERO_ADDRESS = address(0);

    function setUp() public {
        // Set up test accounts.
        vm.startPrank(admin);
        
        CHAIN_ID = block.chainid;

        // Deploy test tokens.
        usdc = new MockERC20("USD Coin", "USDC", AMOUNT_TO_MINT, admin);
        usdt = new MockERC20("Tether USD", "USDT", AMOUNT_TO_MINT, admin);
        dai = new MockERC20("Dai", "DAI", AMOUNT_TO_MINT, admin);
        weth = new MockWETH9("Wrapped Ether", "WETH");

        // Calculate the future Vault contract address.
        uint256 currentNonce = vm.getNonce(admin);
        address futureVaultAddress = vm.computeCreateAddress(admin, currentNonce + 3);

        // Deploy VaultAdmin contract.
        vaultAdmin = new VaultAdmin(
            IVault(futureVaultAddress),
            PAUSE_WINDOW_DURATION,
            BUFFER_PERIOD_DURATION,
            MINIMUM_TRADE_AMOUNT,
            MINIMUM_WRAP_AMOUNT
        );

        // Deploy VaultExtension contract.
        vaultExtension = new VaultExtension(
            IVault(futureVaultAddress),
            IVaultAdmin(address(vaultAdmin))
        );

        // Deploy ProtocolFeeController contract.
        protocolFeeController = new ProtocolFeeController(
            IVault(futureVaultAddress),
            ZERO,
            ZERO
        );
        
        // Deploy Vault contract.
        vault = new Vault(
            IVaultExtension(address(vaultExtension)),
            IAuthorizer(address(vaultAdmin)),
            IProtocolFeeController(address(protocolFeeController))
        );

        // Deploy StablePool contract.
        stablePool = new StablePool(
            StablePool.NewPoolParams({
                name: "Universal Stable Pool",
                symbol: "uUSD",
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: "1.0.0"
            }),
            IVault(address(vault))
        );
        
        // Deploy Router contract.
        router = new Router(
            IVault(address(vault)),
            IWETH(ZERO_ADDRESS),
            GATEWAY,
            UNISWAP_ROUTER,
            "1.0.0" 
        );

        // Register stable pool on VaultExtension contract.
        _registerPool();
        // Initialize the pool with initial liquidity.
        _initializePool();
        // Set up user balances.
        _setupUserBalances();

        vm.stopPrank();
    }

    function _registerPool() internal {
        // Prepare token configurations.
        TokenConfig[] memory tokens = new TokenConfig[](3);
        tokens[0] = TokenConfig({
            token: IERC20(address(usdc)),
            chainId: CHAIN_ID,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(ZERO_ADDRESS),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: IERC20(address(usdt)),
            chainId: CHAIN_ID,
            tokenType: TokenType.STANDARD, 
            rateProvider: IRateProvider(ZERO_ADDRESS),
            paysYieldFees: false
        });
        tokens[2] = TokenConfig({
            token: IERC20(address(dai)),
            chainId: CHAIN_ID,
            tokenType: TokenType.STANDARD, 
            rateProvider: IRateProvider(ZERO_ADDRESS),
            paysYieldFees: false
        });
        
        // Pool role accounts.
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: admin,
            swapFeeManager: admin,
            poolCreator: admin
        });
        
        LiquidityManagement memory liquidityManagement = LiquidityManagement({
            disableUnbalancedLiquidity: false,
            enableAddLiquidityCustom: false,
            enableRemoveLiquidityCustom: false,
            enableDonation: false
        });

        // Call registerPool through the Vault contract (which delegates to VaultExtension).
        IVaultExtension(address(vault)).registerPool(
            address(stablePool), 
            tokens,
            SWAP_FEE_PERCENTAGE,
            uint32(ZERO),
            false,
            roleAccounts,
            ZERO_ADDRESS,
            liquidityManagement
        );
    }
    
    function _initializePool() internal {
        // Prepare initial amounts.
        uint256[] memory initialAmounts = new uint256[](3);
        initialAmounts[0] = INITIAL_LIQUIDITY;
        initialAmounts[1] = INITIAL_LIQUIDITY;
        initialAmounts[2] = INITIAL_LIQUIDITY;
        
        // Prepare tokens array.
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(usdc));
        tokens[1] = IERC20(address(usdt));
        tokens[2] = IERC20(address(dai));
        
        // Approve tokens for the router.
        usdc.approve(address(router), INITIAL_LIQUIDITY);
        usdt.approve(address(router), INITIAL_LIQUIDITY);
        dai.approve(address(router), INITIAL_LIQUIDITY);
        
        // Initialize the pool.
        uint256 bptOut = router.initialize(
            address(stablePool),
            tokens,
            initialAmounts,
            MIN_BPT_AMOUNT_OUT,
            false, // wethIsEth
            ""
        );

        assertTrue(bptOut > 0, "BPT amount should be greater than 0");
    }

    function _setupUserBalances() internal {
        // Transfer tokens to users.
        usdc.transfer(user1, INITIAL_USER_BALANCE);
        usdt.transfer(user1, INITIAL_USER_BALANCE);
        dai.transfer(user1, INITIAL_USER_BALANCE);
        
        usdc.transfer(user2, INITIAL_USER_BALANCE);
        usdt.transfer(user2, INITIAL_USER_BALANCE);
        dai.transfer(user2, INITIAL_USER_BALANCE);
    }
}
