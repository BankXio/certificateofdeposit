// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

interface NFTBonusInterface {

  function getNftsCount(uint _stakeId) external view returns (uint);

  function assignStakeId(address _owner, uint _stakeId) external returns (bool);

  function stakeEnd(address _owner, uint _stakeId) external;

  function nftIdStakedToEntity(uint _nftId) external view returns (address);

}
