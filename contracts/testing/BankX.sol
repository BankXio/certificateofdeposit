// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';

//BBBBBBBBBBBBBBBBB                                         kkkkkkkk         XXXXXXX       XXXXXXX
//B::::::::::::::::B                                        k::::::k         X:::::X       X:::::X
//B::::::BBBBBB:::::B                                       k::::::k         X:::::X       X:::::X
//BB:::::B     B:::::B                                      k::::::k         X::::::X     X::::::X
//  B::::B     B:::::B   aaaaaaaaaaaaa   nnnn  nnnnnnnn      k:::::k kkkkkkk XXX:::::X   X:::::XXX
//  B::::B     B:::::B   a::::::::::::a  n:::nn::::::::nn    k:::::k k:::::k    X:::::X X:::::X
//  B::::BBBBBB:::::B    aaaaaaaaa:::::a n::::::::::::::nn   k:::::k k:::::k     X:::::X:::::X
//  B:::::::::::::BB              a::::a nn:::::::::::::::n  k:::::k k:::::k      X:::::::::X
//  B::::BBBBBB:::::B      aaaaaaa:::::a   n:::::nnnn:::::n  k::::::k:::::k       X:::::::::X
//  B::::B     B:::::B   aa::::::::::::a   n::::n    n::::n  k:::::::::::k       X:::::X:::::X
//  B::::B     B:::::B  a::::aaaa::::::a   n::::n    n::::n  k:::::::::::k      X:::::X X:::::X
//  B::::B     B:::::B a::::a    a:::::a   n::::n    n::::n  k::::::k:::::k  XXX:::::X   X:::::XXX
//BB:::::BBBBBB::::::B a::::a    a:::::a   n::::n    n::::n k::::::k k:::::k X::::::X     X::::::X
//B:::::::::::::::::B  a:::::aaaa::::::a   n::::n    n::::n k::::::k k:::::k X:::::X       X:::::X
//B::::::::::::::::B    a::::::::::aa:::a  n::::n    n::::n k::::::k k:::::k X:::::X       X:::::X
//BBBBBBBBBBBBBBBBB      aaaaaaaaaa  aaaa  nnnnnn    nnnnnn kkkkkkkk kkkkkkk XXXXXXX       XXXXXXX
//
//The first cryptocurrency to pay you interest for minting a stablecoin.
//
//A certificate of deposit designed for the highest yield.

contract BankX is AccessControl, ERC20 {

  uint256 public constant genesis_supply = 2000000000e18;

  address public treasury;

  constructor(
    string memory _name,
    string memory _symbol,
    address _treasury
  ) ERC20(_name, _symbol) {
    require(_treasury != address(0), "Zero address detected");
    treasury = _treasury;

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _mint(treasury, genesis_supply);
  }

  function genesisSupply() public pure returns (uint){
    return genesis_supply;
  }

  function pool_mint(address _entity, uint _amount) external {
    _mint(_entity, _amount);
  }

  function pool_burn_from(address _entity, uint _amount) external {
    _burn(_entity, _amount);
  }

  function setTotalSupplyDifference(uint _amount, bool _increase) external {
    if (_increase) {
      _mint(msg.sender, _amount);
    }
    else {
      _burn(msg.sender, _amount);
    }
  }
}