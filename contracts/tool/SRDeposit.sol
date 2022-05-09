// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Sacred Realm Deposit Contract
 * @author SEALEM-LAB
 * @notice In this contract, players can recharge SR into the game Sacred Realm
 */
contract SRDeposit is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public treasury;
    IERC20 public sr;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(address => uint256) public userDepositAmount;

    event SetAddrs(address treasury, address srAddr);
    event Deposit(
        address indexed operator,
        address indexed user,
        uint256 amount
    );

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set Addrs
     */
    function setAddrs(address _treasury, address srAddr)
        external
        onlyRole(MANAGER_ROLE)
    {
        treasury = _treasury;
        sr = IERC20(srAddr);

        emit SetAddrs(_treasury, srAddr);
    }

    /**
     * @dev Deposit
     */
    function deposit(address user, uint256 amount) external nonReentrant {
        sr.safeTransferFrom(msg.sender, treasury, amount);

        userDepositAmount[user] += amount;

        emit Deposit(msg.sender, user, amount);
    }
}
