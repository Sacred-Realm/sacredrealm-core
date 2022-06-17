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
 * @notice In this contract user can stake ST and harvest SR
 */
contract STStaking is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    bool public openStatus = false;
    uint256 public lastRewardBlock;

    uint256 public srPerBlock = 1e18;

    uint256 public taxDynamicRate = 10;
    uint256 public taxBaseRate = 3000;

    address public treasury;
    IERC20 public st;
    IERC20 public sr;
    IInviting public inviting;

    uint256 public stakedST;
    uint256 public accSRPerStake;
    uint256 public releasedSR;
    uint256 public harvestedSR;

    mapping(address => uint256) public userStakedST;
    mapping(address => uint256) public affiliateStakedST;
    mapping(address => uint256) public userLastAccSRPerStake;
    mapping(address => uint256) public userStoredSR;
    mapping(address => uint256) public userHarvestedSR;

    mapping(address => uint256) public userLastStakeTime;

    event SetTokenInfo(uint256 tokenPerBlock);
    event SetOpenStatus(bool status);
    event SetRate(uint256 taxDynamicRate, uint256 taxBaseRate);
    event SetAddrs(
        address treasury,
        address stAddr,
        address srAddr,
        address invitingAddr
    );
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event HarvestToken(address indexed user, uint256 amount);

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set Token Info
     */
    function setTokenInfo(uint256 tokenPerBlock)
        external
        onlyRole(MANAGER_ROLE)
    {
        srPerBlock = tokenPerBlock;

        emit SetTokenInfo(tokenPerBlock);
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
        address srAddr,
        address invitingAddr
    ) external onlyRole(MANAGER_ROLE) {
        require(
            _treasury != address(0) &&
                stAddr != address(0) &&
                srAddr != address(0) &&
                invitingAddr != address(0),
            "Addrs cannot be empty"
        );

        treasury = _treasury;
        st = IERC20(stAddr);
        sr = IERC20(srAddr);
        inviting = IInviting(invitingAddr);

        emit SetAddrs(_treasury, stAddr, srAddr, invitingAddr);
    }

    /**
     * @dev Deposit
     */
    function deposit(uint256 amount, address inviter) external nonReentrant {
        require(openStatus, "This pool is not opened");

        updatePool();

        if (userStakedST[msg.sender] > 0) {
            uint256 pendingToken = (userStakedST[msg.sender] *
                (accSRPerStake - userLastAccSRPerStake[msg.sender])) / 1e18;
            if (pendingToken > 0) {
                userStoredSR[msg.sender] += pendingToken;
            }
        }

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

        userLastAccSRPerStake[msg.sender] = accSRPerStake;

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

        updatePool();

        uint256 pendingToken = (userStakedST[msg.sender] *
            (accSRPerStake - userLastAccSRPerStake[msg.sender])) / 1e18;
        if (pendingToken > 0) {
            userStoredSR[msg.sender] += pendingToken;
        }

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

        userLastAccSRPerStake[msg.sender] = accSRPerStake;

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Harvest Token
     */
    function harvestToken() external nonReentrant {
        updatePool();

        uint256 pendingToken = (userStakedST[msg.sender] *
            (accSRPerStake - userLastAccSRPerStake[msg.sender])) / 1e18;
        uint256 amount = userStoredSR[msg.sender] + pendingToken;
        require(amount > 0, "Not enough token to harvest");

        userStoredSR[msg.sender] = 0;
        userLastAccSRPerStake[msg.sender] = accSRPerStake;
        userHarvestedSR[msg.sender] += amount;
        harvestedSR += amount;

        sr.safeTransfer(msg.sender, amount);

        emit HarvestToken(msg.sender, amount);
    }

    /**
     * @dev Get Token Total Rewards of a User
     */
    function getTokenTotalRewards(address user)
        external
        view
        returns (uint256)
    {
        return userHarvestedSR[user] + getTokenRewards(user);
    }

    /**
     * @dev Update Pool
     */
    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (block.number > lastRewardBlock && stakedST > 0) {
            uint256 amount = srPerBlock * (block.number - lastRewardBlock);
            accSRPerStake += (amount * 1e18) / stakedST;
            releasedSR += amount;
        }

        lastRewardBlock = block.number;
    }

    /**
     * @dev Get User Tax Rate
     */
    function getUserTaxRate(address user) public view returns (uint256) {
        uint256 reducedRate = ((block.timestamp - userLastStakeTime[user]) /
            1 days) * taxDynamicRate;
        return taxBaseRate > reducedRate ? taxBaseRate - reducedRate : 0;
    }

    /**
     * @dev Get Token Rewards of a User
     */
    function getTokenRewards(address user) public view returns (uint256) {
        uint256 accSRPerStakeTemp = accSRPerStake;

        if (block.number > lastRewardBlock && stakedST > 0) {
            accSRPerStakeTemp +=
                (srPerBlock * (block.number - lastRewardBlock) * 1e18) /
                stakedST;
        }

        return
            userStoredSR[user] +
            ((userStakedST[user] *
                (accSRPerStakeTemp - userLastAccSRPerStake[user])) / 1e18);
    }
}
