// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

/**
 * @title STStaking Interface
 * @author SEALEM-LAB
 * @notice Interface of the STStaking
 */
abstract contract ISTStaking {
    mapping(address => uint256) public userStakedST;
    mapping(address => uint256) public affiliateStakedST;
}
