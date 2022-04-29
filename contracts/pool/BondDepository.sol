// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tool/interface/IPancakePair.sol";

/**
 * @title Bond Depository
 * @author SEALEM-LAB
 * @notice Contract to supply Bond
 */
contract BondDepository is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    uint256 public bondCount;
    mapping(uint256 => address) public lpAddr;
    mapping(uint256 => address) public receivingAddr;
    mapping(uint256 => uint256) public bondMaxSupply;
    mapping(uint256 => uint256) public bondRate;
    mapping(uint256 => uint256) public bondTerm;
    mapping(uint256 => uint256) public bondConclusion;

    mapping(uint256 => uint256) public lpTokenPrices;
    mapping(uint256 => uint256) public bondSoldAmount;

    mapping(address => uint256) public userOrderCount;
    mapping(address => mapping(uint256 => uint256)) public userOrderBondId;
    mapping(address => mapping(uint256 => uint256)) public userOrderAmount;
    mapping(address => mapping(uint256 => uint256)) public userOrderPayout;
    mapping(address => mapping(uint256 => uint256)) public userOrderExpiry;

    event Bond(
        address indexed user,
        uint256 bondId,
        uint256 amount,
        uint256 payout,
        uint256 expiry
    );

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Bond
     */
    function bond(uint256 bondId, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must > 0");
        require(getBondLeftSupply(bondId) >= amount, "Not enough bond supply");
        require(
            receivingAddr[bondId] != address(0),
            "The receiving address of this bond has not been set"
        );
        require(block.timestamp < bondConclusion[bondId], "Bond concluded");

        updatePrice(bondId);

        IERC20(lpAddr[bondId]).safeTransferFrom(
            msg.sender,
            receivingAddr[bondId],
            amount
        );

        uint256 expiry = bondTerm[bondId] + block.timestamp;
        uint256 payout = (lpTokenPrices[bondId] * amount * bondRate[bondId]) /
            1e18 /
            1e4;

        userOrderBondId[msg.sender][userOrderCount[msg.sender]] = bondId;
        userOrderAmount[msg.sender][userOrderCount[msg.sender]] = amount;
        userOrderPayout[msg.sender][userOrderCount[msg.sender]] = payout;
        userOrderExpiry[msg.sender][userOrderCount[msg.sender]] = expiry;
        userOrderCount[msg.sender]++;

        bondSoldAmount[bondId] += amount;

        emit Bond(msg.sender, bondId, amount, payout, expiry);
    }

    /**
     * @dev Update Price
     */
    function updatePrice(uint256 bondId) public {
        (uint112 reserve0, , ) = IPancakePair(lpAddr[bondId]).getReserves();
        lpTokenPrices[bondId] =
            (2 * reserve0 * 1e18) /
            IPancakePair(lpAddr[bondId]).totalSupply();
    }

    /**
     * @dev Get Bond Left Supply
     */
    function getBondLeftSupply(uint256 bondId) public view returns (uint256) {
        return bondMaxSupply[bondId] - bondSoldAmount[bondId];
    }
}
