// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../token/interface/ISN.sol";

/**
 * @title Spawn Sn Batch Contract
 * @author SEALEM-LAB
 * @notice In this contract, SN can be generated in batches
 */
contract SpawnSnBatch is AccessControlEnumerable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // testnet: 0x19482E5043cBb96927fda5541B3859Ebde849456
    ISN public sn = ISN(0xcE4c314f5baeDea571c60CF1D09eCf4304FeCF6A);

    /**
     * @param manager Initialize Manager Role
     */
    constructor(address manager) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, manager);
    }

    /**
     * @dev Get Random
     */
    function getRandom(uint256 seed) public view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        seed,
                        block.difficulty,
                        block.timestamp,
                        block.coinbase,
                        block.number,
                        msg.sender
                    )
                )
            );
    }

    /**
     * @dev Get Level
     */
    function getLevel(uint256[] memory array, uint256 random)
        public
        pure
        returns (uint256)
    {
        uint256 accProbability;
        uint256 level;
        for (uint256 i = 0; i < array.length; i++) {
            accProbability += array[i];
            if (random < accProbability) {
                level = i;
                break;
            }
        }
        return level + 1;
    }

    /**
     * @dev Spawn Sn Batch
     */
    function spawnSnBatch(
        address to,
        uint256 amount,
        uint256 seed,
        uint256[] memory starsProbabilities,
        uint256[] memory powerProbabilities,
        uint256[] memory partProbabilities
    ) external onlyRole(MANAGER_ROLE) {
        uint256[] memory attr = new uint256[](5);
        uint256 random = getRandom(seed);

        for (uint256 i = 0; i < amount; i++) {
            attr[0] = getLevel(starsProbabilities, random % 1e4);
            attr[1] =
                ((getLevel(powerProbabilities, (random % 1e8) / 1e4) - 1) *
                    20) +
                ((((random % 1e12) / 1e8) % 20) + 1);
            attr[2] = (((random % 1e16) / 1e12) % 4) + 1;
            attr[3] = getLevel(partProbabilities, (random % 1e20) / 1e16);
            attr[4] = (((random % 1e24) / 1e20) % 4) + 1;

            sn.spawnSn(attr, to);

            random = getRandom(random);
        }
    }
}
