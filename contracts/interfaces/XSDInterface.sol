// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

interface XSDInterface {

  function balanceOf(address account) external view returns (uint256);
  function pool_mint(address _entity, uint _amount) external;
  function pool_burn_from(address _entity, uint _amount) external;

}
