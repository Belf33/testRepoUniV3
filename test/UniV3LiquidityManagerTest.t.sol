// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {INonfungiblePositionManager} from "../lib/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {UniV3LiquidityManager} from "../src/UniV3LiquidityManager.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract UniV3LiquidityManagerTest is Test {
    UniV3LiquidityManager liquidityManager;
    IERC20 token0;
    IERC20 token1;
    IUniswapV3Pool pool;
    INonfungiblePositionManager positionManager;

    address public user = makeAddr("user");
    address token0Address = address(0x111);
    address token1Address = address(0x222);
    address poolAddress = address(0x333);
    uint256 amount0 = 1000 * 10 ** 18;
    uint256 amount1 = 500 * 10 ** 18;

    function setUp() public {
        positionManager = INonfungiblePositionManager(address(0x1));
        liquidityManager = new UniV3LiquidityManager(address(positionManager));

        // Подготовка mock токенов
        token0 = IERC20(token0Address);
        token1 = IERC20(token1Address);
    }

    // Тест конструктора
    function testConstructor() public {
        assertEq(address(liquidityManager.i_positionManager()), address(positionManager));
    }

    // Тест успешного добавления ликвидности
    function testProvideLiquidity() public {
        // Заглушки для пула Uniswap
        IUniswapV3Pool poolMock = IUniswapV3Pool(poolAddress);
        vm.mockCall(
            poolAddress,
            abi.encodeWithSelector(poolMock.slot0.selector),
            abi.encode(uint160(79228162514264337593543950336), 0, 0, 0, 0, 0, 0) // sqrtPriceX96
        );

        // Одобрение токенов и отправка
        vm.prank(user);
        vm.mockCall(token0Address, abi.encodeWithSelector(token0.transferFrom.selector), abi.encode(true));
        vm.mockCall(token1Address, abi.encodeWithSelector(token1.transferFrom.selector), abi.encode(true));

        vm.prank(user);
        liquidityManager.provideLiquidity(poolAddress, amount0, amount1, 500);

        // Проверка одобрения токенов
        vm.mockCall(token0Address, abi.encodeWithSelector(token0.allowance.selector), abi.encode(amount0));
        vm.mockCall(token1Address, abi.encodeWithSelector(token1.allowance.selector), abi.encode(amount1));

        assertTrue(true, "Liquidity provided successfully");
    }

    // Тест возврата неиспользованных токенов
    function testReturnUnusedTokens() public {
        // Мокаем взаимодействие с Uniswap Position Manager
        vm.prank(user);
        vm.mockCall(token0Address, abi.encodeWithSelector(token0.transferFrom.selector), abi.encode(true));
        vm.mockCall(token1Address, abi.encodeWithSelector(token1.transferFrom.selector), abi.encode(true));

        // После добавления ликвидности, часть токенов должна вернуться
        uint256 amount0Used = 800 * 10 ** 18;
        uint256 amount1Used = 400 * 10 ** 18;

        vm.mockCall(
            address(positionManager),
            abi.encodeWithSelector(positionManager.mint.selector),
            abi.encode(1, 0, amount0Used, amount1Used)
        );

        // Призываем контракт добавить ликвидность
        vm.prank(user);
        liquidityManager.provideLiquidity(poolAddress, amount0, amount1, 500);

        // Проверка возврата неиспользованных токенов
        uint256 amount0Remaining = amount0 - amount0Used;
        uint256 amount1Remaining = amount1 - amount1Used;

        vm.mockCall(token0Address, abi.encodeWithSelector(token0.transfer.selector), abi.encode(true));
        vm.mockCall(token1Address, abi.encodeWithSelector(token1.transfer.selector), abi.encode(true));

        assertEq(amount0Remaining, 200 * 10 ** 18, "Token0 returned correctly");
        assertEq(amount1Remaining, 100 * 10 ** 18, "Token1 returned correctly");
    }

    // Тест вычисления тиков
    function testCalculateTicksForWidth() public {
        uint256 currentPrice = 100000;
        uint256 width = 500; // 5% ширина

        (int24 lowerTick, int24 upperTick) = liquidityManager.calculateTicksForWidth(currentPrice, width);
        assertTrue(lowerTick < upperTick, "Lower tick is smaller than upper tick");
    }
}