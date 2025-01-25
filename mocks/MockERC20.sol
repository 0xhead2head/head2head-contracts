// SPDX_License-Identifier: Unlicense
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MERC","MERC") {
        _mint(msg.sender, 1000000e18);
    }
}