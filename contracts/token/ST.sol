// SPDX-License-Identifier: MIT
pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Sealem Token
 * @author SEALEM-LAB
 * @notice Contract to supply ST
 */
contract ST is ERC20 {
    constructor() ERC20("Sealem Token", "ST") {
        _mint(msg.sender, 1e8 * 1e18);
    }
}
