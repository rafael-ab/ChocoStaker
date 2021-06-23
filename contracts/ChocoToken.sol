// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/drafts/ERC20Permit.sol";

contract ChocoToken is ERC20, ERC20Burnable, Ownable, ERC20Permit {
    constructor() ERC20("ChocoToken", "CHOCO") ERC20Permit("ChocoToken") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
