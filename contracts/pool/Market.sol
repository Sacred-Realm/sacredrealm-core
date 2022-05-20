// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../pool/interface/IInviting.sol";

/**
 * @title Market Contract
 * @author SEALEM-LAB
 * @notice In this contract users can trade NFT
 */
contract Market is ERC721Holder, AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IInviting public inviting;
    address public treasury;
    uint256 public fee = 500;

    mapping(address => mapping(uint256 => address)) public token;
    mapping(address => mapping(uint256 => uint256)) public price;
    mapping(address => mapping(uint256 => address)) public seller;

    mapping(address => mapping(address => uint256)) public userTokenBuyAmount;
    mapping(address => mapping(address => uint256))
        public affiliateTokenBuyAmount;

    event SetAddrs(address invitingAddr, address treasury);
    event SetFee(uint256 fee);
    event Sell(
        address indexed seller,
        address[] nfts,
        uint256[] nftIds,
        address[] tokens,
        uint256[] prices
    );
    event Cancel(address indexed seller, address[] nfts, uint256[] nftIds);
    event Buy(
        address indexed buyer,
        address[] sellers,
        address[] nfts,
        uint256[] nftIds,
        address[] tokens,
        uint256[] prices
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
    function setAddrs(address invitingAddr, address _treasury)
        external
        onlyRole(MANAGER_ROLE)
    {
        inviting = IInviting(invitingAddr);
        treasury = _treasury;

        emit SetAddrs(invitingAddr, _treasury);
    }

    /**
     * @dev Set Fee
     */
    function setFee(uint256 _fee) external onlyRole(MANAGER_ROLE) {
        require(_fee <= 5000, "The fee ratio cannot exceed 50%");
        fee = _fee;

        emit SetFee(_fee);
    }

    /**
     * @dev Sell
     */
    function sell(
        address[] memory nfts,
        uint256[] memory nftIds,
        address[] memory tokens,
        uint256[] memory prices
    ) external nonReentrant {
        for (uint256 i = 0; i < nftIds.length; i++) {
            IERC721(nfts[i]).safeTransferFrom(
                msg.sender,
                address(this),
                nftIds[i]
            );

            token[nfts[i]][nftIds[i]] = tokens[i];
            price[nfts[i]][nftIds[i]] = prices[i];
            seller[nfts[i]][nftIds[i]] = msg.sender;
        }

        emit Sell(msg.sender, nfts, nftIds, tokens, prices);
    }

    /**
     * @dev Cancel
     */
    function cancel(address[] memory nfts, uint256[] memory nftIds)
        external
        nonReentrant
    {
        for (uint256 i = 0; i < nftIds.length; i++) {
            require(
                seller[nfts[i]][nftIds[i]] == msg.sender,
                "This NFT is not own"
            );

            delete token[nfts[i]][nftIds[i]];
            delete price[nfts[i]][nftIds[i]];
            delete seller[nfts[i]][nftIds[i]];

            IERC721(nfts[i]).safeTransferFrom(
                address(this),
                msg.sender,
                nftIds[i]
            );
        }

        emit Cancel(msg.sender, nfts, nftIds);
    }

    /**
     * @dev Buy
     */
    function buy(
        address[] memory nfts,
        uint256[] memory nftIds,
        address inviter
    ) external payable nonReentrant {
        address[] memory tokens = new address[](nftIds.length);
        uint256[] memory prices = new uint256[](nftIds.length);
        address[] memory sellers = new address[](nftIds.length);
        address userInviter = inviting.managerBindInviter(msg.sender, inviter);

        for (uint256 i = 0; i < nftIds.length; i++) {
            tokens[i] = token[nfts[i]][nftIds[i]];
            prices[i] = price[nfts[i]][nftIds[i]];
            sellers[i] = seller[nfts[i]][nftIds[i]];

            delete token[nfts[i]][nftIds[i]];
            delete price[nfts[i]][nftIds[i]];
            delete seller[nfts[i]][nftIds[i]];

            uint256 feeAmount = (prices[i] * fee) / 1e4;
            uint256 sellAmount = prices[i] - feeAmount;

            if (tokens[i] == address(0)) {
                payable(treasury).transfer(feeAmount);
                payable(sellers[i]).transfer(sellAmount);
            } else {
                IERC20(tokens[i]).safeTransferFrom(
                    msg.sender,
                    treasury,
                    feeAmount
                );
                IERC20(tokens[i]).safeTransferFrom(
                    msg.sender,
                    sellers[i],
                    sellAmount
                );
            }

            IERC721(nfts[i]).safeTransferFrom(
                address(this),
                msg.sender,
                nftIds[i]
            );

            userTokenBuyAmount[msg.sender][tokens[i]] += prices[i];
            if (userInviter != address(0)) {
                affiliateTokenBuyAmount[userInviter][tokens[i]] += prices[i];
            }
        }

        emit Buy(msg.sender, sellers, nfts, nftIds, tokens, prices);
    }
}
