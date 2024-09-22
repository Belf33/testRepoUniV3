// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../lib/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @author Belii Dmitii
/// @title Менеджер ликвидности Uniswap V3
contract UniV3LiquidityManager {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable i_positionManager;

    constructor(address _positionManager) {
        i_positionManager = INonfungiblePositionManager(_positionManager);
    }

    /// @notice Вложить ликвидность в позицию Uniswap V3 с заданной шириной
    /// @param poolAddress Адрес пула Uniswap V3
    /// @param amount0 Количество первого актива
    /// @param amount1 Количество второго актива
    /// @param width Ширина позиции в соответствии с формулой
    function provideLiquidity(
        address poolAddress,
        uint256 amount0,
        uint256 amount1,
        uint256 width
    ) external {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // Получение текущего состояния пула
        (uint160 sqrtPriceX96, , , , , ,) = pool.slot0();

        // Конвертация sqrtPriceX96 в нормальную цену
        uint256 currentPrice = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (2 ** 192);

        // Вычисляем диапазон цен в зависимости от ширины
        (int24 lowerTick, int24 upperTick) = calculateTicksForWidth(currentPrice, width);

        // Получаем токены пула
        address token0 = pool.token0();
        address token1 = pool.token1();

        // Одобряем токены для positionManager
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);

        _adjustAllowance(IERC20(token0), address(i_positionManager), amount0);
        _adjustAllowance(IERC20(token1), address(i_positionManager), amount1);

        // Добавляем ликвидность через positionManager
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: pool.fee(),
            tickLower: lowerTick,
            tickUpper: upperTick,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 120
        });

        (, , uint256 amount0Used, uint256 amount1Used) = i_positionManager.mint(params);

        // Возвращаем оставшиеся токены
        if (amount0 > amount0Used) {
            IERC20(token0).safeTransfer(msg.sender, amount0 - amount0Used);
        }
        if (amount1 > amount1Used) {
            IERC20(token1).safeTransfer(msg.sender, amount1 - amount1Used);
        }
    }

    /// @notice Вычисление нижнего и верхнего тиков на основе ширины позиции
    /// @param currentPrice Текущая цена пула
    /// @param width Ширина позиции
    /// @return lowerTick и upperTick в формате int24
    function calculateTicksForWidth(uint256 currentPrice, uint256 width) public pure returns (int24 lowerTick, int24 upperTick) {
        uint256 upperPrice = (currentPrice * (10000 + width)) / 10000;
        uint256 lowerPrice = (currentPrice * (10000 - width)) / 10000;

        lowerTick = getTickAtPrice(lowerPrice);
        upperTick = getTickAtPrice(upperPrice);
    }

    /// @notice Преобразовать цену в тик
    /// @param price Цена актива
    /// @return Тик в формате int24
    function getTickAtPrice(uint256 price) public pure returns (int24) {
        // Пример простой конверсии цены в тик для иллюстрации.
        // В реальном контракте юзаем правильную формулу для вычисления тиков из цены.
        int24 tick = int24(uint24(price / 2**96));  // Приведение типов с uint160 к int24
        return tick;
    }

    /// @notice Корректировка разрешений для токенов
    /// @param token Токен, для которого нужно изменить разрешение
    /// @param spender Адрес, которому нужно предоставить разрешение
    /// @param amount Необходимое количество для одобрения
    function _adjustAllowance(IERC20 token, address spender, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);

        if (currentAllowance < amount) {
            // Если текущего разрешения недостаточно, увеличиваем его
            token.safeIncreaseAllowance(spender, amount - currentAllowance);
        } else if (currentAllowance > amount) {
            // Если разрешение больше, чем нужно, уменьшаем его
            token.safeDecreaseAllowance(spender, currentAllowance - amount);
        }
    }
}

