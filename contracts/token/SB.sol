// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../token/interface/IST.sol";

/**
 * @title Sacred Realm Box
 * @author SEALEM-LAB
 * @notice Contract to supply SB
 */
contract SB is ERC721Enumerable, AccessControlEnumerable, ReentrancyGuard {
    using SafeERC20 for IST;
    using Strings for uint256;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    IST public st;

    string public baseURI;
    uint256 public boxPrice = 100e18;
    address public receivingAddr = 0x0000000000000000000000000000000000000020;

    event SetBaseURI(string uri);
    event BuyBoxes(address indexed user, uint256 amount);
    event OpenBoxes(address indexed user, uint256 amount);

    /**
     * @param manager Initialize Manager Role
     * @param stAddr Initialize ST Address
     */
    constructor(address manager, address stAddr)
        ERC721("Sacred Realm Box", "SB")
    {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);

        st = IST(stAddr);
    }

    /**
     * @dev Allows the manager to set the base URI to be used for all token IDs
     */
    function setBaseURI(string memory uri) external onlyRole(MANAGER_ROLE) {
        baseURI = uri;

        emit SetBaseURI(uri);
    }

    /**
     * @dev Users buy the boxes
     */
    function buyBoxes(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must > 0");

        st.safeTransferFrom(msg.sender, receivingAddr, amount * boxPrice);

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(msg.sender, totalSupply());
        }

        emit BuyBoxes(msg.sender, amount);
    }

    /**
     * @dev Users open the boxes
     */
    function openBoxes(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must > 0");

        for (uint256 i = 0; i < amount; i++) {
            safeTransferFrom(
                msg.sender,
                receivingAddr,
                tokenOfOwnerByIndex(msg.sender, 0)
            );
        }

        emit OpenBoxes(msg.sender, amount);
    }

    /**
     * @dev Safe Transfer From Batch
     */
    function safeTransferFromBatch(
        address from,
        address to,
        uint256[] calldata tokenIds
    ) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            safeTransferFrom(from, to, tokenIds[i]);
        }
    }

    /**
     * @dev Returns a list of token IDs owned by `user` given a `cursor` and `size` of its token list
     */
    function tokensOfOwnerBySize(
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > balanceOf(user) - cursor) {
            length = balanceOf(user) - cursor;
        }

        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = tokenOfOwnerByIndex(user, cursor + i);
        }

        return (values, cursor + length);
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for a token ID
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
                : "";
    }

    /**
     * @dev IERC165-supportsInterface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlEnumerable, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
