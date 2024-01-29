// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import '@openzeppelin/contracts/utils/Context.sol';
import './lib/Ownable.sol';
import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract NFTBonus is ERC1155Holder, Ownable {

  event Staked(address indexed entity, uint nftId, uint timestamp);
  event AssignedStakeId(address indexed entity, uint nftId, uint stakeId, uint timestamp);
  event Unstaked(address indexed entity, uint nftId, uint stakeId, uint timestamp);

  mapping(uint => uint[]) public nftsStakedToCD;
  mapping(address => uint[]) public entityStakedNftIds;
  mapping(address => uint[]) public entityStakedNftIdsTemp;
  mapping(uint => address) public nftIdStakedToEntity;
  mapping(uint => uint) public nftStakedAt;

  IERC1155 public NFT;
  address public cdContractAddress;

  uint internal constant MAX_NFTS_STAKED = 5;
  bool public initiated;

  function init() external {
    require(initiated == false, "initiated");

    _transferOwnership(_msgSender());
    initiated = true;
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override (ERC1155Receiver) returns (bool) {
    return interfaceId == type(IERC1155).interfaceId ||
    interfaceId == type(IERC1155MetadataURI).interfaceId ||
    super.supportsInterface(interfaceId);
  }

  function getNftsCount(uint _stakeId) public view returns (uint) {
    return nftsStakedToCD[_stakeId].length;
  }

  function getEntityStakedNftIds(address _owner) public view returns (uint[] memory) {
    return entityStakedNftIds[_owner];
  }

  function assignStakeId(address _owner, uint _stakeId) public returns (bool) {
    require(msg.sender == cdContractAddress, "not allowed");

    for (uint8 i = 0; i < entityStakedNftIdsTemp[_owner].length; i++) {
      uint nftId = entityStakedNftIdsTemp[_owner][i];

      nftsStakedToCD[_stakeId].push(nftId);
      emit AssignedStakeId(_owner, nftId, _stakeId, block.timestamp);
    }

    delete entityStakedNftIdsTemp[_owner];

    return true;
  }

  function stakeNFT(uint _nftId) external payable {
    require(NFT.balanceOf(msg.sender, _nftId) != 0, "no nft");
    require(entityStakedNftIdsTemp[msg.sender].length < MAX_NFTS_STAKED, "over limit");
    require(nftIdStakedToEntity[_nftId] == address(0), "already staked");

    nftIdStakedToEntity[_nftId] = msg.sender;
    nftStakedAt[_nftId] = block.timestamp;

    bool alreadyExists = false;
    for (uint8 i = 0; i < entityStakedNftIds[msg.sender].length; i++) {
      if (entityStakedNftIds[msg.sender][i] == _nftId) {
        alreadyExists = true;
        break;
      }
    }
    if (!alreadyExists) {
      entityStakedNftIds[msg.sender].push(_nftId);
    }

    alreadyExists = false;
    for (uint8 i = 0; i < entityStakedNftIdsTemp[msg.sender].length; i++) {
      if (entityStakedNftIdsTemp[msg.sender][i] == _nftId) {
        alreadyExists = true;
        break;
      }
    }
    if (!alreadyExists) {
      entityStakedNftIdsTemp[msg.sender].push(_nftId);
    }

    if (NFT.balanceOf(address(this), _nftId) == 0) {
      NFT.safeTransferFrom(msg.sender, address(this), _nftId, 1, bytes(""));
    }

    emit Staked(msg.sender, _nftId, block.timestamp);
  }

  function stakeEnd(address _owner, uint _stakeId) external {
    require(msg.sender == cdContractAddress, "not allowed");

    uint256 nftsStakedToCDLength = nftsStakedToCD[_stakeId].length;

    while (nftsStakedToCDLength > 0) {
      uint nftId = nftsStakedToCD[_stakeId][nftsStakedToCDLength - 1];
      require(_owner == nftIdStakedToEntity[nftId], "not owner");
      unstakeNFT(nftId, _stakeId, _owner);
      // As we change global nftsStakedToCD inside other function the length will change too.
      nftsStakedToCDLength = nftsStakedToCD[_stakeId].length;
    }
  }

  function unstakeNFT(uint _nftId, uint _stakeId, address _owner) internal {
    if (_nftId == 0 || _stakeId == 0) return;
    require(nftIdStakedToEntity[_nftId] == _owner, "not staked");

    nftIdStakedToEntity[_nftId] = address(0);

    for (uint8 i = 0; i < entityStakedNftIds[_owner].length; i++) {
      if (entityStakedNftIds[_owner][i] == _nftId) {
        _deleteIndex(entityStakedNftIds[_owner], i);
        break;
      }
    }
    for (uint8 i = 0; i < nftsStakedToCD[_stakeId].length; i++) {
      if (nftsStakedToCD[_stakeId][i] == _nftId) {
        _deleteIndex(nftsStakedToCD[_stakeId], i);
        break;
      }
    }

    NFT.safeTransferFrom(address(this), _owner, _nftId, 1, bytes(""));

    emit Unstaked(_owner, _nftId, _stakeId, block.timestamp);
  }

  function updateNFTContract(address _nftContract) public onlyOwner() {
    NFT = IERC1155(_nftContract);
  }

  function updateCDContract(address _cdContract) public onlyOwner() {
    cdContractAddress = _cdContract;
  }

  function _deleteIndex(uint[] storage array, uint index) internal {
    uint lastIndex = array.length - 1;
    uint lastEntry = array[lastIndex];
    if (index == lastIndex) {
      array.pop();
    } else {
      array[index] = lastEntry;
      array.pop();
    }
  }
}