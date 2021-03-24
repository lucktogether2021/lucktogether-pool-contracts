// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0 <0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./RegistryInterface.sol";

/// @title Interface that allows a user to draw an address using an index
contract Registry is Ownable, RegistryInterface {
  address private pointer;

  event Registered(address indexed pointer);

  function register(address _pointer) external onlyOwner {
    pointer = _pointer;

    emit Registered(pointer);
  }

  function lookup() external override view returns (address) {
    return pointer;
  }
}
