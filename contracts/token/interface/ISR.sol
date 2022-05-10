// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SR Interface
 * @author SEALEM-LAB
 * @notice Interface of the SR
 */
abstract contract ISR is IERC20 {
    uint256 public fee;
    mapping(address => bool) public isFeeExempt;
}
