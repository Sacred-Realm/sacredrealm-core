// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "../token/interface/ISN.sol";

/**
 * @title Windvane Launchpad
 * @author SEALEM-LAB
 * @notice Contract to supply Sacred Realm Box to Windvane Launchpad
 */
contract WindvaneLaunchpad is ERC721Holder {
    uint256 public LAUNCH_MAX_SUPPLY = 500;
    uint256 public LAUNCH_SUPPLY;

    //testnet: 0x390266537F02CeF0FAf1Db2EAf0C91925E6c518e
    ISN public sb = ISN(0xA8De106949D494E2b346E4496695Abe71C4b02eC);

    constructor() {}

    function getMaxLaunchpadSupply() public view returns (uint256) {
        return LAUNCH_MAX_SUPPLY;
    }

    function getLaunchpadSupply() public view returns (uint256) {
        return LAUNCH_SUPPLY;
    }

    function mintTo(address to, uint256 size) external payable {
        require(to != address(0), "can't mint to empty address");
        require(size > 0, "size must greater than zero");
        require(
            LAUNCH_SUPPLY + size <= LAUNCH_MAX_SUPPLY,
            "max supply reached"
        );

        payable(0x280da57048043Ca84ad0FaF3C6d20D25851EB14f).transfer(0.37 * 1e18 * size);

        uint256[] memory sbIds = new uint256[](size);
        (sbIds, ) = sb.tokensOfOwnerBySize(address(this), 0, size);
        sb.safeTransferFromBatch(address(this), to, sbIds);

        LAUNCH_SUPPLY += size;
    }
}
