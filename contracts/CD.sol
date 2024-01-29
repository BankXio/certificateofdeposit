// SPDX-License-Identifier: UNLICENSED

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
//Currency Creators Manifesto
//
//Our world faces an urgent crisis of currency manipulation, theft and inflation.  Under the current system,
// currency is controlled by and benefits elite families, governments and large banking institutions.  We believe
// currencies should be minted by and benefit the individual, not the establishment.  It is time to take back the
// control of and the freedom that money can provide.
//
//BankX is rebuilding the legacy banking system from the ground up by providing you with the capability to create
// currency and be in complete control of wealth creation with a concept we call ‘Individual Created Digital Currency’
// (ICDC). You own the collateral.  You mint currency.  You earn interest.  You leverage without the risk of liquidation.
// You stake to earn even more returns.  All of this is done with complete autonomy and decentralization.  BankX has
// built a stablecoin for Individual Freedom.
//
//BankX is the antidote for the malevolent financial system bringing in a new future of freedom where you are in
// complete control with no middlemen, bank or central bank between you and your finances. This capability to create
// currency and be in complete control of wealth creation will be in the hands of every individual that uses BankX.
//
//By 2030, we will rid the world of the corrupt, tyrannical and incompetent banking system replacing it with a system
// where billions of people will be in complete control of their financial future.  Everyone will be given ultimate
// freedom to use their assets to create currency, earn interest and multiply returns to accomplish their individual
// goals.  The mission of BankX is to be the first to mint $1 trillion in stablecoin.
//
//We will bring about this transformation by attracting people that believe what we believe.  We will partner with
// other blockchain protocols and build decentralized applications that drive even more usage.  Finally, we will deploy
// a private network that is never connected to the Internet to communicate between counterparties, that allows for
// blockchain-to-blockchain interoperability and stores private keys and cryptocurrency wallets.  Our ecosystem,
// network and platform has never been seen in the market and provides us with a long term sustainable competitive advantage.
//
//We value individual freedom.
//We believe in financial autonomy.
//We are anti-establishment.
//We envision a future of self-empowerment.

pragma solidity 0.8.16;

import "./GlobalsAndStats.sol";
//import "hardhat/console.sol";

contract CD is GlobalsAndStats {
  bool public initiated;

  function init() external {
    require(initiated == false, "initiated");

    _transferOwnership(_msgSender());

    /* Initialize global cdRate to 1 */
    globals.cdRate = uint40(1 * CD_RATE_SCALE);
    globals.dailyDataCount = 1;
    launchTime = block.timestamp;
    LPBBonusPercent = 20;
    LPB = 364 * 100 / LPBBonusPercent;  // 1820

    initiated = true;
  }

  /**
   * @dev PUBLIC FACING: Open a stake.
     * @param newStakedXs Number of Xs to stake
     * @param newStakedDays Number of days to stake
     */
  function stakeStart(uint256 newStakedXs, uint256 newStakedDays) external
  {
    GlobalsCache memory g;
    GlobalsCache memory gSnapshot;
    _globalsLoad(g, gSnapshot);

    updateLPB();

    /* Enforce the minimum stake time */
    require(newStakedDays >= MIN_STAKE_DAYS, "newStakedDays low");

    /* Check if log data needs to be updated */
    _dailyDataUpdateAuto(g);

    _stakeStart(g, newStakedXs, newStakedDays);

    /* Remove staked Xs from balance of staker */
    bankXContract.pool_burn_from(msg.sender, newStakedXs * 1e10);

    _globalsSync(g, gSnapshot);
  }

  /**
   * @dev PUBLIC FACING: Unlocks a completed stake, distributing the proceeds of any penalty
     * immediately. The staker must still call stakeEnd() to retrieve their stake return (if any).
     * @param stakerAddr Address of staker
     * @param stakeIndex Index of stake within stake list
     * @param stakeIdParam The stake's id
     */
  function stakeGoodAccounting(address stakerAddr, uint256 stakeIndex, uint40 stakeIdParam)
  external
  {
    GlobalsCache memory g;
    GlobalsCache memory gSnapshot;
    _globalsLoad(g, gSnapshot);

    require(stakeLists[stakerAddr].length != 0, "empty stake list");
    require(stakeIndex < stakeLists[stakerAddr].length, "stakeIndex invalid");

    StakeStore storage stRef = stakeLists[stakerAddr][stakeIndex];

    /* Get stake copy */
    StakeCache memory st;
    _stakeLoad(stRef, stakeIdParam, st);

    /* Stake must have served full term */
    require(g._currentDay >= st._lockedDay + st._stakedDays, "Stake not fully served");

    /* Stake must still be locked */
    require(st._unlockedDay == 0, "Stake already unlocked");

    /* Check if log data needs to be updated */
    _dailyDataUpdateAuto(g);

    /* Unlock the completed stake */
    _stakeUnlock(g, st);

    /* stakeReturn value is unused here */
    (, uint256 payout, uint256 penalty, uint256 cappedPenalty) = _stakePerformance(
      g,
      st,
      st._stakedDays
    );

    _emitStakeGoodAccounting(
      stakerAddr,
      stakeIdParam,
      st._stakedXs,
      st._stakeShares,
      payout,
      penalty
    );

    if (cappedPenalty != 0) {
      _splitPenaltyProceeds(g, cappedPenalty);
    }

    /* st._unlockedDay has changed */
    _stakeUpdate(stRef, st);

    _globalsSync(g, gSnapshot);
  }

  /**
   * @dev PUBLIC FACING: Closes a stake. The order of the stake list can change so
     * a stake id is used to reject stale indexes.
     * @param stakeIndex Index of stake within stake list
     * @param stakeId The stake's id
     */
  function stakeEnd(uint256 stakeIndex, uint40 stakeId) external {
    GlobalsCache memory g;
    GlobalsCache memory gSnapshot;
    _globalsLoad(g, gSnapshot);

    updateLPB();

    StakeStore[] storage stakeListRef = stakeLists[msg.sender];

    require(stakeListRef.length != 0, "empty stake list");
    require(stakeIndex < stakeListRef.length, "stakeIndex invalid");

    /* Get stake copy */
    StakeCache memory st;
    _stakeLoad(stakeListRef[stakeIndex], stakeId, st);

    /* Check if log data needs to be updated */
    _dailyDataUpdateAuto(g);

    uint256 servedDays = 0;

    bool prevUnlocked = (st._unlockedDay != 0);
    uint256 stakeReturn;
    uint256 payout = 0;
    uint256 penalty = 0;
    uint256 cappedPenalty = 0;

    if (g._currentDay >= st._lockedDay) {
      if (prevUnlocked) {
        /* Previously unlocked in stakeGoodAccounting(), so must have served full term */
        servedDays = st._stakedDays;
      } else {
        _stakeUnlock(g, st);

        servedDays = g._currentDay - st._lockedDay;
        if (servedDays > st._stakedDays) {
          servedDays = st._stakedDays;
        }
      }

      (stakeReturn, payout, penalty, cappedPenalty) = _stakePerformance(g, st, servedDays);
    } else {
      /* Stake hasn't been added to the total yet, so no penalties or rewards apply */
      g._nextStakeSharesTotal -= st._stakeShares;
      stakeReturn = st._stakedXs;
    }

    _emitStakeEnd(
      stakeId,
      st._stakedXs,
      st._stakeShares,
      payout,
      penalty,
      servedDays,
      prevUnlocked
    );

    if (cappedPenalty != 0 && !prevUnlocked) {
      /* Split penalty proceeds only if not previously unlocked by stakeGoodAccounting() */
      _splitPenaltyProceeds(g, cappedPenalty);
    }

    /* Pay the stake return, if any, to the staker */
    if (stakeReturn != 0) {
      bankXContract.pool_mint(msg.sender, stakeReturn * 1e10);

      /* Update the share rate if necessary */
      _cdRateUpdate(g, st, stakeReturn);
    }
    g._lockedXsTotal -= st._stakedXs;

    _stakeRemove(stakeListRef, stakeIndex);

    _globalsSync(g, gSnapshot);

    nftBonusContract.stakeEnd(msg.sender, stakeId);
  }

  /**
   * @dev PUBLIC FACING: Return the current stake count for a staker address
     * @param stakerAddr Address of staker
     */
  function stakeCount(address stakerAddr) external view returns (uint256)
  {
    return stakeLists[stakerAddr].length;
  }

  /**
   * @dev Open a stake.
     * @param g Cache of stored globals
     * @param newStakedXs Number of Xs to stake
     * @param newStakedDays Number of days to stake
     */
  function _stakeStart(GlobalsCache memory g, uint256 newStakedXs, uint256 newStakedDays) internal
  {
    /* Enforce the maximum stake time */
    require(newStakedDays <= MAX_STAKE_DAYS, "newStakedDays high");

    uint40 newStakeId = ++g._latestStakeId;

    nftBonusContract.assignStakeId(msg.sender, newStakeId);

    uint256 bonusXs = _stakeStartBonusXs(newStakedXs, newStakedDays, newStakeId);
    uint256 newStakeShares = (newStakedXs + bonusXs) * CD_RATE_SCALE / g._cdRate;

//    console.log("bonusXs", bonusXs);
//    console.log("newStakedXs", newStakedXs);
//    console.log("newStakeShares", newStakeShares);

    /* Ensure newStakedXs is enough for at least one stake share */
    require(newStakeShares != 0, "newStakedXs must be >= min cdRate");

    /*
        The stakeStart timestamp will always be part-way through the current
        day, so it needs to be rounded-up to the next day to ensure all
        stakes align with the same fixed calendar days. The current day is
        already rounded-down, so rounded-up is current day + 1.
    */
    uint256 newLockedDay = g._currentDay + 1;

    /* Create Stake */
    _stakeAdd(
      stakeLists[msg.sender],
      newStakeId,
      newStakedXs,
      newStakeShares,
      newLockedDay,
      newStakedDays
    );

    _emitStakeStart(newStakeId, newStakedXs, newStakeShares, newStakedDays);

    /* Stake is added to total in the next round, not the current round */
    g._nextStakeSharesTotal += newStakeShares;

    /* Track total staked Xs for inflation calculations */
    g._lockedXsTotal += newStakedXs;
  }

  /**
   * @dev Calculates total stake payout including rewards for a multi-day range
     * @param stakeSharesParam Param from stake to calculate bonuses for
     * @param beginDay First day to calculate bonuses for
     * @param endDay Last day (non-inclusive) of range to calculate bonuses for
     * @return payout Payout in Xs
     */
  function _calcPayoutRewards(uint256 stakeSharesParam, uint256 beginDay, uint256 endDay)
  private view returns (uint256 payout)
  {
    for (uint256 day = beginDay; day < endDay; day++) {
      payout += dailyData[day].dayPayoutTotal * stakeSharesParam
      / dailyData[day].dayStakeSharesTotal;
    }

    return payout;
  }

  /**
   * @dev Calculate bonus Xs for a new stake, if any
     * @param newStakedXs Number of Xs to stake
     * @param newStakedDays Number of days to stake
     */
  function _stakeStartBonusXs(uint256 newStakedXs, uint256 newStakedDays, uint40 newStakeId) private view returns (uint256 bonusXs)
  {
    /*
        LONGER PAYS BETTER:

        If longer than 1 day stake is committed to, each extra day
        gives bonus shares of approximately 0.0548%, which is approximately 20%
        extra per year of increased stake length committed to, but capped to a
        maximum of 200% extra.

        extraDays       =  stakedDays - 1

        longerBonus%    = (extraDays / 364) * 33.33%
                        = (extraDays / 364) / 3
                        =  extraDays / 1092
                        =  extraDays / LPB

        extraDays       =  longerBonus% * 1092

        extraDaysMax    =  longerBonusMax% * 1092
                        =  200% * 1092
                        =  2184
                        =  LPB_MAX_DAYS

        BIGGER PAYS BETTER:

        Bonus percentage scaled 0% to 10% for the first 150M BankX of stake.

        biggerBonus%    = (cappedXs /  BPB_MAX_XS) * 10%
                        = (cappedXs /  BPB_MAX_XS) / 10
                        =  cappedXs / (BPB_MAX_XS * 10)
                        =  cappedXs /  BPB

        COMBINED:

        combinedBonus%  =            longerBonus%  +  biggerBonus%

                                  cappedExtraDays     cappedXs
                        =         ---------------  +  ------------
                                        LPB               BPB

                            cappedExtraDays * BPB     cappedXs * LPB
                        =   ---------------------  +  ------------------
                                  LPB * BPB               LPB * BPB

                            cappedExtraDays * BPB  +  cappedXs * LPB
                        =   --------------------------------------------
                                              LPB  *  BPB

        bonusXs     = Xs * combinedBonus%
                        = Xs * (cappedExtraDays * BPB  +  cappedXs * LPB) / (LPB * BPB)
    */
    uint256 cappedExtraDays = 0;

    /* Must be more than 1 day for Longer-Pays-Better */
    if (newStakedDays > 1) {
      cappedExtraDays = newStakedDays <= LPB_MAX_DAYS ? newStakedDays - 1 : LPB_MAX_DAYS;
    }

    uint256 cappedStakedXs = newStakedXs <= BPB_MAX_XS ? newStakedXs : BPB_MAX_XS;

//    console.log("newStakedXs", newStakedXs);
//    console.log("cappedStakedXs", cappedStakedXs);


    bonusXs = cappedExtraDays * BPB + cappedStakedXs * LPB;

//    console.log("LPB", LPB);
//    console.log("cappedStakedXs * LPB", cappedStakedXs * LPB);
//    console.log("BPB", BPB);
//    console.log("cappedExtraDays * BPB", cappedExtraDays * BPB);
//    console.log("cappedExtraDays * BPB + cappedStakedXs * LPB", bonusXs);

    bonusXs = newStakedXs * bonusXs / (LPB * BPB);

//    console.log("newStakedXs * bonusXs / (LPB * BPB)", bonusXs);

    return bonusXs + bonusXs * nftBonusContract.getNftsCount(newStakeId) / 10;
  }

  function updateLPB() public {
    bool lastUpdatedWeekAgo = (block.timestamp - LPBLastUpdated) >= 7 days;
    bool positiveInflation = bankXContract.totalSupply() > bankXContract.genesis_supply();

    if (positiveInflation && LPBBonusPercent < 40 && lastUpdatedWeekAgo) {
      LPBBonusPercent = LPBBonusPercent + 5;
      LPBLastUpdated = block.timestamp;
    }
    else if (!positiveInflation && LPBBonusPercent > 20) {
      LPBBonusPercent = 20;
      LPBLastUpdated = block.timestamp;
    }

    LPB = 36400 / LPBBonusPercent;
  }

  function _stakeUnlock(GlobalsCache memory g, StakeCache memory st) private pure {
    g._stakeSharesTotal -= st._stakeShares;
    st._unlockedDay = g._currentDay;
  }

  function _stakePerformance(GlobalsCache memory g, StakeCache memory st, uint256 servedDays) private view
  returns (uint256 stakeReturn, uint256 payout, uint256 penalty, uint256 cappedPenalty){
    if (servedDays < st._stakedDays) {
      (payout, penalty) = _calcPayoutAndEarlyPenalty(
        g,
        st._lockedDay,
        st._stakedDays,
        servedDays,
        st._stakeShares
      );
      stakeReturn = st._stakedXs + payout;
    } else {
      // servedDays must == stakedDays here
      payout = _calcPayoutRewards(
        st._stakeShares,
        st._lockedDay,
        st._lockedDay + servedDays
      );
      stakeReturn = st._stakedXs + payout;

      penalty = _calcLatePenalty(st._lockedDay, st._stakedDays, st._unlockedDay, stakeReturn);
    }
    if (penalty != 0) {
      if (penalty > stakeReturn) {
        /* Cannot have a negative stake return */
        cappedPenalty = stakeReturn;
        stakeReturn = 0;
      } else {
        /* Remove penalty from the stake return */
        cappedPenalty = penalty;
        stakeReturn -= cappedPenalty;
      }
    }
    return (stakeReturn, payout, penalty, cappedPenalty);
  }

  function _calcPayoutAndEarlyPenalty(GlobalsCache memory g, uint256 lockedDay, uint256 stakedDays, uint256 servedDays, uint256 stakeShares)
  private view returns (uint256 payout, uint256 penalty) {
    uint256 servedEndDay = lockedDay + servedDays;

    /* 50% of stakedDays (rounded up) with a minimum applied */
    uint256 penaltyDays = (stakedDays + 1) / 2;
    if (penaltyDays < EARLY_PENALTY_MIN_DAYS) {
      penaltyDays = EARLY_PENALTY_MIN_DAYS;
    }

    if (servedDays == 0) {
      /* Fill penalty days with the estimated average payout */
      uint256 expected = _estimatePayoutRewardsDay(g, stakeShares, lockedDay);
      penalty = expected * penaltyDays;
      return (payout, penalty);
      // Actual payout was 0
    }

    if (penaltyDays < servedDays) {
      /*
          Simplified explanation of intervals where end-day is non-inclusive:

          penalty:    [lockedDay  ...  penaltyEndDay)
          delta:                      [penaltyEndDay  ...  servedEndDay)
          payout:     [lockedDay  .......................  servedEndDay)
      */
      uint256 penaltyEndDay = lockedDay + penaltyDays;
      penalty = _calcPayoutRewards(stakeShares, lockedDay, penaltyEndDay);

      uint256 delta = _calcPayoutRewards(stakeShares, penaltyEndDay, servedEndDay);
      payout = penalty + delta;
      return (payout, penalty);
    }

    /* penaltyDays >= servedDays  */
    payout = _calcPayoutRewards(stakeShares, lockedDay, servedEndDay);

    if (penaltyDays == servedDays) {
      penalty = payout;
    } else {
      /*
          (penaltyDays > servedDays) means not enough days served, so fill the
          penalty days with the average payout from only the days that were served.
      */
      penalty = payout * penaltyDays / servedDays;

      if (LPBBonusPercent > 20) {
        penalty += calculateLPBPenalty(payout, stakedDays, servedDays);
      }
    }
    return (payout, penalty);
  }

  function calculateLPBPenalty(uint payout, uint stakedDays, uint servedDays) public view returns (uint) {
    return payout * (((LPBBonusPercent - 20) * (stakedDays - servedDays)) / 10) * 11;
  }

  function _calcLatePenalty(uint256 lockedDay, uint256 stakedDays, uint256 unlockedDay, uint256 rawStakeReturn)
  private pure returns (uint256){
    /* Allow grace time before penalties accrue */
    uint256 maxUnlockedDay = lockedDay + stakedDays + LATE_PENALTY_GRACE_DAYS;
    if (unlockedDay <= maxUnlockedDay) {
      return 0;
    }

    /* Calculate penalty as a percentage of stake return based on time */
    return rawStakeReturn * (unlockedDay - maxUnlockedDay) / LATE_PENALTY_SCALE_DAYS;
  }

  function _splitPenaltyProceeds(GlobalsCache memory g, uint256 penalty) private
  {
    /* Split a penalty 50:50 between Origin and stakePenaltyTotal */
    uint256 splitPenalty = penalty / 2;

    if (splitPenalty != 0) {
      bankXContract.pool_mint(ORIGIN_ADDR, splitPenalty * 1e10);
    }

    /* Use the other half of the penalty to account for an odd-numbered penalty */
    splitPenalty = penalty - splitPenalty;
    g._stakePenaltyTotal += splitPenalty;
  }

  function _cdRateUpdate(GlobalsCache memory g, StakeCache memory st, uint256 stakeReturn) private
  {
    if (stakeReturn > st._stakedXs) {
      /*
          Calculate the new cdRate that would yield the same number of shares if
          the user re-staked this stakeReturn, factoring in any bonuses they would
          receive in stakeStart().
      */
      uint256 bonusXs = _stakeStartBonusXs(stakeReturn, st._stakedDays, st._stakeId);
      uint256 newCDRate = (stakeReturn + bonusXs) * CD_RATE_SCALE / st._stakeShares;

      // Realistically this can't happen, but capped to prevent anyway.
      if (newCDRate > CD_RATE_MAX) {
        newCDRate = CD_RATE_MAX;
      }

      if (newCDRate > g._cdRate) {
        g._cdRate = newCDRate;

        _emitCDRateChange(newCDRate, st._stakeId);
      }
    }
  }

  function _emitStakeStart(uint40 stakeId, uint256 stakedXs, uint256 stakeShares, uint256 stakedDays) private
  {
    emit StakeStart(
      uint256(uint40(block.timestamp))
      | (uint256(uint72(stakedXs)) << 40)
      | (uint256(uint72(stakeShares)) << 112)
      | (uint256(uint16(stakedDays)) << 184)
      | 0,
      msg.sender,
      stakeId
    );
  }

  function _emitStakeGoodAccounting(
    address stakerAddr,
    uint40 stakeId,
    uint256 stakedXs,
    uint256 stakeShares,
    uint256 payout,
    uint256 penalty
  )
  private
  {
    emit StakeGoodAccounting(
      uint256(uint40(block.timestamp))
      | (uint256(uint72(stakedXs)) << 40)
      | (uint256(uint72(stakeShares)) << 112)
      | (uint256(uint72(payout)) << 184),
      uint256(uint72(penalty)),
      stakerAddr,
      stakeId,
      msg.sender
    );
  }

  function _emitStakeEnd(
    uint40 stakeId,
    uint256 stakedXs,
    uint256 stakeShares,
    uint256 payout,
    uint256 penalty,
    uint256 servedDays,
    bool prevUnlocked
  )
  private
  {
    emit StakeEnd(
      uint256(uint40(block.timestamp))
      | (uint256(uint72(stakedXs)) << 40)
      | (uint256(uint72(stakeShares)) << 112)
      | (uint256(uint72(payout)) << 184),
      uint256(uint72(penalty))
      | (uint256(uint16(servedDays)) << 72)
      | (prevUnlocked ? (1 << 88) : 0),
      msg.sender,
      stakeId
    );
  }

  function _emitCDRateChange(uint256 cdRate, uint40 stakeId)
  private
  {
    emit CDRateChange(
      uint256(uint40(block.timestamp))
      | (uint256(uint40(cdRate)) << 40),
      stakeId
    );
  }
}