// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/**
 * @title SN Interface
 * @author SEALEM-LAB
 * @notice Interface of the SN
 */
abstract contract ISN is IERC721Enumerable {
    mapping(uint256 => uint256) public spawntime;

    mapping(uint256 => mapping(string => uint256)) public data;
    mapping(uint256 => mapping(string => uint256[])) public datas;

    function spawnSn(address to) external virtual returns (uint256);

    function setData(
        uint256 snId,
        string calldata slot,
        uint256 _data
    ) external virtual;

    function setDatas(
        uint256 snId,
        string calldata slot,
        uint256[] calldata _datas
    ) external virtual;

    function safeTransferFromBatch(
        address from,
        address to,
        uint256[] calldata tokenIds
    ) external virtual;

    function getDatas(uint256 snId, string calldata slot)
        external
        view
        virtual
        returns (uint256[] memory);

    function tokensOfOwnerBySize(
        address user,
        uint256 cursor,
        uint256 size
    ) external view virtual returns (uint256[] memory, uint256);

    function getRandomNumber(
        uint256 snId,
        string calldata slot,
        uint256 base,
        uint256 range
    ) external pure virtual returns (uint256);
}
