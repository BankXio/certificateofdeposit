// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

interface CollateralPoolInterface {

  function bankx_minted_count() external view returns (uint);

  function collatDollarBalance() external view returns (uint);

}
