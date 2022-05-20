// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title Inviting Contract
 * @author SEALEM-LAB
 * @notice In this contract user can bind inviter
 */
contract Inviting is AccessControlEnumerable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => address) public userInviter;

    event BindInviter(address indexed user, address inviter);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Manager Bind Inviter
     */
    function managerBindInviter(address user, address inviter)
        external
        onlyRole(MANAGER_ROLE)
        returns (address)
    {
        if (
            inviter != address(0) &&
            inviter != user &&
            userInviter[user] == address(0) &&
            userInviter[inviter] != user
        ) {
            userInviter[user] = inviter;

            emit BindInviter(user, inviter);
        }

        return userInviter[user];
    }
}
