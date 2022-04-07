// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Sacred Realm Box
 * @author SEALEM-LAB
 * @notice Contract to supply SB
 */
contract SB is ERC721Enumerable, AccessControlEnumerable {
    using Strings for uint256;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    string public baseURI;

    event SetBaseURI(string uri);
    event SpawnSb(address indexed to, uint256 sbId);

    /**
     * @param manager Initialize Manager Role
     */
    constructor(
        address manager
    ) ERC721("Sacred Realm Box", "SB") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Allows the manager to set the base URI to be used for all token IDs
     */
    function setBaseURI(string memory uri) external onlyRole(MANAGER_ROLE) {
        baseURI = uri;

        emit SetBaseURI(uri);
    }

    /**
     * @dev Spawn a New Sb to an Address
     */
    function spawnSb(address to)
        external
        returns (uint256)
    {
        uint256 newSbId = totalSupply();

        _safeMint(to, newSbId);

        emit SpawnSb(to, newSbId);

        return newSbId;
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
