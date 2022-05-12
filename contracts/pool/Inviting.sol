// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Inviting Contract
 * @author SEALEM-LAB
 * @notice In this contract user can bind inviter
 */
contract Inviting is ReentrancyGuard {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => address) public userInviter;

    event BindInviter(address indexed user, address inviter);

    constructor() {}

    /**
     * @dev Bind Inviter
     */
    function bindInviter(address inviter)
        external
        nonReentrant
        returns (address)
    {
        if (
            inviter != address(0) &&
            inviter != msg.sender &&
            userInviter[msg.sender] == address(0) &&
            userInviter[inviter] != msg.sender
        ) {
            userInviter[msg.sender] = inviter;

            emit BindInviter(msg.sender, inviter);
        }

        return userInviter[msg.sender];
    }
}
