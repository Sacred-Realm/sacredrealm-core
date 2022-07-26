// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "../token/interface/ISN.sol";

/**
 * @title Coow Launchpad
 * @author SEALEM-LAB
 * @notice Contract to supply Sacred Realm Box to Coow Launchpad
 */
contract CoowLaunchpad is ERC721Holder {
    uint256 public LAUNCH_MAX_SUPPLY = 300;
    uint256 public LAUNCH_SUPPLY;

    //testnet: 0x9Fe278481bC1cC56906091d5ab2b5Eff679Ff18A
    address public LAUNCHPAD = 0x074E710A0B3DF69a795C6c15fb80255a12E9E646;

    //testnet: 0x390266537F02CeF0FAf1Db2EAf0C91925E6c518e
    ISN public sb = ISN(0xA8De106949D494E2b346E4496695Abe71C4b02eC);

    constructor() {}

    modifier onlyLaunchpad() {
        require(LAUNCHPAD != address(0), "launchpad address must set");
        require(msg.sender == LAUNCHPAD, "must call by launchpad");
        _;
    }

    function getMaxLaunchpadSupply() public view returns (uint256) {
        return LAUNCH_MAX_SUPPLY;
    }

    function getLaunchpadSupply() public view returns (uint256) {
        return LAUNCH_SUPPLY;
    }

    function mintTo(address to, uint256 size) external onlyLaunchpad {
        require(to != address(0), "can't mint to empty address");
        require(size > 0, "size must greater than zero");
        require(
            LAUNCH_SUPPLY + size <= LAUNCH_MAX_SUPPLY,
            "max supply reached"
        );

        uint256[] memory sbIds = new uint256[](size);
        (sbIds, ) = sb.tokensOfOwnerBySize(address(this), 0, size);
        sb.safeTransferFromBatch(address(this), to, sbIds);

        LAUNCH_SUPPLY += size;
    }
}
