// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import '@openzeppelin/contracts/access/AccessControl.sol';
import './lib/Ownable.sol';
import './lib/ERC1155Pausable.sol';
import './lib/ERC1155Supply.sol';
import "./interfaces/XSDInterface.sol";
import "./interfaces/CollateralPoolInterface.sol";
import "./interfaces/NFTBonusInterface.sol";
import "hardhat/console.sol";

contract BankXNFT is AccessControl, Ownable, ERC1155Pausable, ERC1155Supply {

  bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
  bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

  address payable public constant COLLECTOR = payable(0xBDAD0dd0c0207094a341bD930a5562de3aCCE8Eb);
  address public constant ADMIN_KEY_ADDR = 0xC34faEea3605a168dBFE6afCd6f909714F844cd7;

  XSDInterface public XSDContract;
  CollateralPoolInterface public collateralPoolContract;
  NFTBonusInterface public nftBonusContract;

  uint public nftTiers;
  mapping(uint => uint) public nftTierLowerBound;
  mapping(uint => uint) public nftTierUpperBound;
  mapping(uint => uint) public nftTierPrice;

  mapping(uint => uint) public nftRewardsClaimed;

  uint public lastNftId;
  uint private hundredMillionTier;
  uint tvlUpdatedAt;

  bool public initiated;

  mapping(address => address) public entityReferrer;
  mapping(address => uint) public entityTotalReferred;
  mapping(address => address[]) public entityReferrals;
  mapping(address => uint[2][]) public referrerMintedAtAndCount;

  function init() external {
    require(initiated == false, "initiated");

    _transferOwnership(_msgSender());

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(DEFAULT_ADMIN_ROLE, ADMIN_KEY_ADDR);
    _setupRole(MINTER_ROLE, ADMIN_KEY_ADDR);
    _setupRole(PAUSER_ROLE, ADMIN_KEY_ADDR);

    initiated = true;
  }

  function setURI(string memory newUri, uint batch) public onlyRole(DEFAULT_ADMIN_ROLE) {
    _setURI(newUri, batch);
  }

  function pause() public onlyRole(PAUSER_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(PAUSER_ROLE) {
    _unpause();
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override (AccessControl, ERC1155) returns (bool) {
    return interfaceId == type(IERC1155).interfaceId ||
    interfaceId == type(IERC1155MetadataURI).interfaceId ||
    super.supportsInterface(interfaceId);
  }

  function mint(address to, uint amount, address referrer, bytes memory data) public payable {
    require(entityReferrer[to] == address(0) || entityReferrer[to] == referrer, "wrong referrer");
    uint totalPrice = 0;

    for (uint8 i = 1; i <= amount; i++) {
      lastNftId ++;

      for (uint8 j = 1; j <= nftTiers; j++) {
        if (lastNftId >= nftTierLowerBound[j] && lastNftId <= nftTierUpperBound[j]) {
          require(nftTierPrice[j] > 0, "price zero");

          totalPrice += nftTierPrice[j];
          _mint(to, lastNftId, 1, data);

          break;
        }
      }
    }

    require(msg.value >= totalPrice, "not enough");

    uint refCommission = totalPrice / 10;
    if (referrer == address(0) || COLLECTOR == referrer) {
      sendETH(COLLECTOR, totalPrice);
    }
    else {
      if (entityReferrer[to] == address(0)) {
        entityReferrer[to] = referrer;
        entityReferrals[referrer].push(to);
      }

      entityTotalReferred[referrer] += amount;
      referrerMintedAtAndCount[referrer].push([block.timestamp, amount]);

      sendETH(COLLECTOR, totalPrice - refCommission);
      sendETH(payable(referrer), refCommission);
    }

    updateTVLReached();
  }

  function mintAdmin(address to, uint amount, bytes memory data) public onlyRole(MINTER_ROLE) {
    for (uint8 i = 1; i <= amount; i++) {
      lastNftId ++;
      _mint(to, lastNftId, 1, data);
    }

    updateTVLReached();
  }

  function sendETH(address payable recipient, uint amount) internal {
    require(address(this).balance >= amount, "insufficient balance");

    (bool success,) = recipient.call{value : amount}("");
    require(success, "send failed");
  }

  function updateTVLReached() public {
    bool updatedDayAgo = tvlUpdatedAt + 1 days <= block.timestamp;
    if (address(collateralPoolContract) != address(0) && updatedDayAgo) {
      uint newTier = collateralPoolContract.collatDollarBalance() / (100000000 * 1e18);
      hundredMillionTier = hundredMillionTier < newTier ? newTier : hundredMillionTier;
      tvlUpdatedAt = block.timestamp;
    }
  }

  function getRewards(uint nftId) public view returns (uint) {
    require(exists(nftId), "doesn't exist");
    if (hundredMillionTier == 0) return 0;

    uint reward = hundredMillionTier * 200;
    if (nftId <= 5000) {
      reward += 800;
    }

    reward = reward * 1e18;

    return reward - nftRewardsClaimed[nftId];
  }

  function claimRewards(uint nftId, uint amount) public {
    require(amount <= getRewards(nftId), "nothing to claim");
    require(balanceOf(msg.sender, nftId) != 0 || nftBonusContract.nftIdStakedToEntity(nftId) == msg.sender, "not owner");

    nftRewardsClaimed[nftId] += amount;
    XSDContract.pool_mint(msg.sender, amount);
  }

  function _beforeTokenTransfer(address operator, address from, address to, uint[] memory ids, uint[] memory amounts, bytes memory data)
  internal whenNotPaused override(ERC1155Supply, ERC1155Pausable)
  {
    super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
  }

  function updatePrice(uint _tier, uint _lowerBound, uint _upperBound, uint _value) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (nftTiers < _tier) {
      nftTiers = _tier;
    }

    nftTierLowerBound[_tier] = _lowerBound;
    nftTierUpperBound[_tier] = _upperBound;
    nftTierPrice[_tier] = _value;
  }

  function updateXSDContractContract(address _XSDContract) public onlyOwner() {
    XSDContract = XSDInterface(_XSDContract);
  }

  function updateCollateralPoolContract(address _collateralPoolContract) public onlyOwner() {
    collateralPoolContract = CollateralPoolInterface(_collateralPoolContract);
  }

  function updateNFTBonusContract(address _nftBonusContract) public onlyOwner() {
    nftBonusContract = NFTBonusInterface(_nftBonusContract);
  }
}
