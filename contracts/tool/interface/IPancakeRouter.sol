// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

interface IPancakeRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}