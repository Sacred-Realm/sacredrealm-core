// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../pool/interface/IInviting.sol";

/**
 * @title STStaking Contract
 * @author SEALEM-LAB
 * @notice In this contract user can stake ST
 */
contract STStaking is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    bool public openStatus = false;

    uint256 public taxDynamicRate = 10;
    uint256 public taxBaseRate = 3000;

    address public treasury;
    IERC20 public st;
    IInviting public inviting;

    uint256 public stakedST;

    mapping(address => uint256) public userStakedST;
    mapping(address => uint256) public affiliateStakedST;

    mapping(address => uint256) public userLastStakeTime;

    event SetOpenStatus(bool status);
    event SetRate(uint256 taxDynamicRate, uint256 taxBaseRate);
    event SetAddrs(address treasury, address stAddr, address invitingAddr);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set Open Status
     */
    function setOpenStatus(bool status) external onlyRole(MANAGER_ROLE) {
        openStatus = status;

        emit SetOpenStatus(status);
    }

    /**
     * @dev Set Rate
     */
    function setRate(uint256 _taxDynamicRate, uint256 _taxBaseRate)
        external
        onlyRole(MANAGER_ROLE)
    {
        require(_taxBaseRate <= 3000, "The tax base rate cannot exceed 30%");

        taxDynamicRate = _taxDynamicRate;
        taxBaseRate = _taxBaseRate;

        emit SetRate(_taxDynamicRate, _taxBaseRate);
    }

    /**
     * @dev Set Addrs
     */
    function setAddrs(
        address _treasury,
        address stAddr,
        address invitingAddr
    ) external onlyRole(MANAGER_ROLE) {
        require(
            _treasury != address(0) &&
                stAddr != address(0) &&
                invitingAddr != address(0),
            "Addrs cannot be empty"
        );

        treasury = _treasury;
        st = IERC20(stAddr);
        inviting = IInviting(invitingAddr);

        emit SetAddrs(_treasury, stAddr, invitingAddr);
    }

    /**
     * @dev Deposit
     */
    function deposit(uint256 amount, address inviter) external nonReentrant {
        require(openStatus, "This pool is not opened");

        if (amount > 0) {
            st.safeTransferFrom(msg.sender, address(this), amount);

            userStakedST[msg.sender] += amount;
            address userInviter = inviting.managerBindInviter(
                msg.sender,
                inviter
            );
            if (userInviter != address(0)) {
                affiliateStakedST[userInviter] += amount;
            }

            stakedST += amount;

            userLastStakeTime[msg.sender] = block.timestamp;
        }

        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev Withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(
            userStakedST[msg.sender] >= amount,
            "Not enough ST to withdraw"
        );

        if (amount > 0) {
            userStakedST[msg.sender] -= amount;
            address userInviter = inviting.userInviter(msg.sender);
            if (userInviter != address(0)) {
                affiliateStakedST[userInviter] -= amount;
            }

            stakedST -= amount;

            uint256 feeAmount = (amount * getUserTaxRate(msg.sender)) / 1e4;
            uint256 withdrawAmount = amount - feeAmount;

            st.safeTransfer(treasury, feeAmount);
            st.safeTransfer(msg.sender, withdrawAmount);
        }

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Get User Tax Rate
     */
    function getUserTaxRate(address user) public view returns (uint256) {
        uint256 reducedRate = ((block.timestamp - userLastStakeTime[user]) /
            1 days) * taxDynamicRate;
        return taxBaseRate > reducedRate ? taxBaseRate - reducedRate : 0;
    }
}
