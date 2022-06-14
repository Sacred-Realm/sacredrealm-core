// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Initial Dex Offering
 * @author SEALEM-LAB
 * @notice Contract to supply IDO Tokens
 */
contract IDO is AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(uint256 => address) public idoTokens;
    mapping(uint256 => uint256) public tokenPrices;
    mapping(uint256 => address) public tokenAddrs;
    mapping(uint256 => address) public receivingAddrs;
    mapping(uint256 => uint256) public tokenMaxSupplys;
    mapping(uint256 => uint256) public userBuyLimits;
    mapping(uint256 => uint256) public startTimes;
    mapping(uint256 => uint256) public endTimes;
    mapping(uint256 => bool) public whiteListFlags;

    mapping(uint256 => uint256) public tokenSoldout;
    mapping(address => mapping(uint256 => uint256)) public userTokenPurchased;
    mapping(uint256 => EnumerableSet.AddressSet) private whiteList;

    event SetIDOInfo(
        uint256 idoId,
        address idoToken,
        uint256 tokenPrice,
        address tokenAddr,
        address receivingAddr,
        uint256 tokenMaxSupply,
        uint256 userBuyLimit,
        uint256 starTime,
        uint256 endTime,
        bool whiteListFlag
    );
    event AddWhiteList(uint256 idoId, address[] whiteUsers);
    event RemoveWhiteList(uint256 idoId, address[] whiteUsers);
    event BuyToken(address indexed user, uint256 amount, uint256 idoId);

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Set IDO Info
     */
    function setIDOInfo(
        uint256 idoId,
        address idoToken,
        uint256 tokenPrice,
        address tokenAddr,
        address receivingAddr,
        uint256 tokenMaxSupply,
        uint256 userBuyLimit,
        uint256 startTime,
        uint256 endTime,
        bool whiteListFlag
    ) external onlyRole(MANAGER_ROLE) {
        idoTokens[idoId] = idoToken;
        tokenPrices[idoId] = tokenPrice;
        tokenAddrs[idoId] = tokenAddr;
        receivingAddrs[idoId] = receivingAddr;
        tokenMaxSupplys[idoId] = tokenMaxSupply;
        userBuyLimits[idoId] = userBuyLimit;
        startTimes[idoId] = startTime;
        endTimes[idoId] = endTime;
        whiteListFlags[idoId] = whiteListFlag;

        emit SetIDOInfo(
            idoId,
            idoToken,
            tokenPrice,
            tokenAddr,
            receivingAddr,
            tokenMaxSupply,
            userBuyLimit,
            startTime,
            endTime,
            whiteListFlag
        );
    }

    /**
     * @dev Add White List
     */
    function addWhiteList(uint256 idoId, address[] memory whiteUsers)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < whiteUsers.length; i++) {
            whiteList[idoId].add(whiteUsers[i]);
        }

        emit AddWhiteList(idoId, whiteUsers);
    }

    /**
     * @dev Remove White List
     */
    function removeWhiteList(uint256 idoId, address[] memory whiteUsers)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < whiteUsers.length; i++) {
            whiteList[idoId].remove(whiteUsers[i]);
        }

        emit RemoveWhiteList(idoId, whiteUsers);
    }

    /**
     * @dev Users buy token
     */
    function buyToken(uint256 amount, uint256 idoId)
        external
        payable
        nonReentrant
    {
        require(amount > 0, "Amount must > 0");
        require(
            idoTokens[idoId] != address(0),
            "The token of this IDO has not been set"
        );
        require(
            block.timestamp >= startTimes[idoId],
            "This IDO has not started"
        );
        require(block.timestamp <= endTimes[idoId], "This IDO has ended");
        require(
            getUserTokenLeftSupply(idoId, msg.sender) >= amount,
            "Amount exceeds the buy limit"
        );
        require(getTokenLeftSupply(idoId) >= amount, "Not enough token supply");
        require(
            tokenPrices[idoId] > 0,
            "The price of this IDO has not been set"
        );
        require(
            receivingAddrs[idoId] != address(0),
            "The receiving address of this IDO has not been set"
        );
        if (whiteListFlags[idoId]) {
            require(
                whiteList[idoId].contains(msg.sender),
                "Your address must be on the whitelist"
            );
        }

        uint256 price = (amount * tokenPrices[idoId]) / 1e18;
        if (tokenAddrs[idoId] == address(0)) {
            require(msg.value == price, "Price mismatch");
            payable(receivingAddrs[idoId]).transfer(price);
        } else {
            IERC20 token = IERC20(tokenAddrs[idoId]);
            token.safeTransferFrom(msg.sender, receivingAddrs[idoId], price);
        }

        IERC20(idoTokens[idoId]).safeTransfer(msg.sender, amount);

        userTokenPurchased[msg.sender][idoId] += amount;
        tokenSoldout[idoId] += amount;

        emit BuyToken(msg.sender, amount, idoId);
    }

    /**
     * @dev Get White List Existence
     */
    function getWhiteListExistence(uint256 idoId, address user)
        external
        view
        returns (bool)
    {
        return whiteList[idoId].contains(user);
    }

    /**
     * @dev Get Token Left Supply
     */
    function getTokenLeftSupply(uint256 idoId) public view returns (uint256) {
        return tokenMaxSupplys[idoId] - tokenSoldout[idoId];
    }

    /**
     * @dev Get User Token Left Supply
     */
    function getUserTokenLeftSupply(uint256 idoId, address user)
        public
        view
        returns (uint256)
    {
        return userBuyLimits[idoId] - userTokenPurchased[user][idoId];
    }
}
