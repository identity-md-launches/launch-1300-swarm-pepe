// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed supply; the launch factory alone performs the launch distribution.
contract SPEPE is ERC20 {
    constructor() ERC20("Swarm Pepe", "SPEPE") {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}
