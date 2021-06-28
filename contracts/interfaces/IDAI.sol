// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IDAI {
    function name() external pure returns (string memory);
    
    function transfer(address dst, uint256 wad) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) external returns (bool);

    function mint(address usr, uint256 wad) external;

    function burn(address usr, uint256 wad) external;

    function approve(address usr, uint256 wad) external returns (bool);

    function push(address usr, uint256 wad) external;

    function pull(address usr, uint256 wad) external;

    function move(
        address src,
        address dst,
        uint256 wad
    ) external;

    function nonces(address owner) external view returns (uint256);

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
