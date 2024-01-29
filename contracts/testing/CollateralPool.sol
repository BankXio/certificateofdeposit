// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import "hardhat/console.sol";


contract CollateralPool {

  uint public minted;

  constructor()  {}

  function collatDollarBalance() public view returns (uint){
    return minted * 1e18;
  }

  function bankx_minted_count() public pure returns (uint) {
    return uint(10000000000);
  }

  function setCollatDollarBalance(uint _amount) public {
    minted = _amount;
  }
}