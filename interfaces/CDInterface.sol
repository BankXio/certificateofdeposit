// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

interface NFTBonusInterface {

  function getNftsCount(address _owner, uint _stakeId) external view returns (uint);

}
