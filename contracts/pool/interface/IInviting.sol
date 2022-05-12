// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

/**
 * @title Inviting Interface
 * @author SEALEM-LAB
 * @notice Interface of the Inviting
 */
abstract contract IInviting {
    mapping(address => address) public userInviter;

    function bindInviter(address inviter) external virtual returns (address);
}
