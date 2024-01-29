// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import './lib/Ownable.sol';
import "./interfaces/BankXInterface.sol";
import "./interfaces/NFTBonusInterface.sol";
import "./interfaces/CollateralPoolInterface.sol";

contract GlobalsAndStats is Ownable {

  /*  DailyDataUpdate

      uint40            timestamp       -->  data0 [ 39:  0]
      uint16            beginDay        -->  data0 [ 55: 40]
      uint16            endDay          -->  data0 [ 71: 56]
      bool              isAutoUpdate    -->  data0 [ 79: 72]
      address  indexed  updaterAddr
  */
  event DailyDataUpdate(
    uint256 data0,
    address indexed updaterAddr
  );

  /*  StakeStart

      uint40            timestamp       -->  data0 [ 39:  0]
      address  indexed  stakerAddr
      uint40   indexed  stakeId
      uint72            stakedXs        -->  data0 [111: 40]
      uint72            stakeShares     -->  data0 [183:112]
      uint16            stakedDays      -->  data0 [199:184]
      bool              isAutoStake     -->  data0 [207:200]
  */
  event StakeStart(
    uint256 data0,
    address indexed stakerAddr,
    uint40 indexed stakeId
  );

  /*  StakeGoodAccounting

      uint40            timestamp       -->  data0 [ 39:  0]
      address  indexed  stakerAddr
      uint40   indexed  stakeId
      uint72            stakedXs        -->  data0 [111: 40]
      uint72            stakeShares     -->  data0 [183:112]
      uint72            payout          -->  data0 [255:184]
      uint72            penalty         -->  data1 [ 71:  0]
      address  indexed  senderAddr
  */
  event StakeGoodAccounting(
    uint256 data0,
    uint256 data1,
    address indexed stakerAddr,
    uint40 indexed stakeId,
    address indexed senderAddr
  );

  /*  StakeEnd

      uint40            timestamp       -->  data0 [ 39:  0]
      address  indexed  stakerAddr
      uint40   indexed  stakeId
      uint72            stakedXs        -->  data0 [111: 40]
      uint72            stakeShares     -->  data0 [183:112]
      uint72            payout          -->  data0 [255:184]
      uint72            penalty         -->  data1 [ 71:  0]
      uint16            servedDays      -->  data1 [ 87: 72]
      bool              prevUnlocked    -->  data1 [ 95: 88]
  */
  event StakeEnd(
    uint256 data0,
    uint256 data1,
    address indexed stakerAddr,
    uint40 indexed stakeId
  );

  /*  CDRateChange
      // pricing control CD rate - requires BankX to make price go up.
      // keeps staking ahead of inflation
      uint40            timestamp    -->  data0 [ 39:  0]
      uint40            CDRate       -->  data0 [ 79: 40]
      uint40   indexed  stakeId
  */
  event CDRateChange(uint256 data0, uint40 indexed stakeId);

  /* Origin BankX address */
  address internal constant ORIGIN_ADDR = 0xC3F015a2cBDF48866763311932e40001e18296A4;
  BankXInterface public bankXContract;
  NFTBonusInterface public nftBonusContract;
  CollateralPoolInterface public collateralPoolContract;

  /* Size of a Xs or CD uint */
  uint256 internal constant X_UINT_SIZE = 72;

  /* Stake timing parameters */
  uint256 internal constant MIN_STAKE_DAYS = 1;
  uint256 internal constant MAX_STAKE_DAYS = 5555; // Approx 15 years

  uint256 internal constant EARLY_PENALTY_MIN_DAYS = 90;

  uint256 internal constant LATE_PENALTY_GRACE_DAYS = 2 * 7;
  uint256 internal constant LATE_PENALTY_SCALE_DAYS = 100 * 7;

  /* Time of contract launch */
  uint256 internal launchTime;

  /* Stake shares Longer Pays Better bonus constants used by _stakeStartBonusXs() */
  uint256 public LPBBonusPercent;
  uint256 public LPB;
  uint256 public constant LPB_MAX_DAYS = 3640;
  uint256 public LPBLastUpdated;

  /* Stake shares Bigger Pays Better bonus constants used by _stakeStartBonusXs() */
  uint256 private constant XS_PER_BANKX = 1e8;
  uint256 private constant BPB_BONUS_PERCENT = 10;
  uint256 private constant BPB_MAX_BANKX = 150 * 1e6;
  uint256 internal constant BPB_MAX_XS = BPB_MAX_BANKX * XS_PER_BANKX;
  uint256 internal constant BPB = BPB_MAX_XS * 100 / BPB_BONUS_PERCENT;

  /* Share rate is scaled to increase precision */
  uint256 internal constant CD_RATE_SCALE = 1e5;

  /* Share rate max (after scaling) */
  uint256 internal constant CD_RATE_UINT_SIZE = 40;
  uint256 internal constant CD_RATE_MAX = (1 << CD_RATE_UINT_SIZE) - 1;

  /* Globals expanded for memory (except _latestStakeId) and compact for storage */
  struct GlobalsCache {
    // 1
    uint256 _lockedXsTotal;
    uint256 _nextStakeSharesTotal;
    uint256 _cdRate;
    uint256 _stakePenaltyTotal;
    // 2
    uint256 _dailyDataCount;
    uint256 _stakeSharesTotal;
    uint40 _latestStakeId;
    //
    uint256 _currentDay;
  }

  struct GlobalsStore {
    // 1
    uint72 lockedXsTotal;
    uint72 nextStakeSharesTotal;
    uint40 cdRate;
    uint72 stakePenaltyTotal;
    // 2
    uint16 dailyDataCount;
    uint72 stakeSharesTotal;
    uint40 latestStakeId;
  }

  GlobalsStore public globals;

  /* Daily data */
  struct DailyDataStore {
    uint72 dayPayoutTotal;
    uint72 dayStakeSharesTotal;
    uint56 dayUnclaimedSatoshisTotal;
  }

  mapping(uint256 => DailyDataStore) public dailyData;

  /* Stake expanded for memory (except _stakeId) and compact for storage */
  struct StakeCache {
    uint40 _stakeId;
    uint256 _stakedXs;
    uint256 _stakeShares;
    uint256 _lockedDay;
    uint256 _stakedDays;
    uint256 _unlockedDay;
  }

  struct StakeStore {
    uint40 stakeId;
    uint72 stakedXs;
    uint72 stakeShares;
    uint16 lockedDay;
    uint16 stakedDays;
    uint16 unlockedDay;
  }

  mapping(address => StakeStore[]) public stakeLists;

  /* Temporary state for calculating daily rounds */
  struct DailyRoundState {
    uint256 _allocSupplyCached;
    uint256 _mintOriginBatch;
    uint256 _payoutTotal;
  }

  /**
   * @dev PUBLIC FACING: Optionally update daily data for a smaller
     * range to reduce gas cost for a subsequent operation
     * @param beforeDay Only update days before this day number (optional; 0 for current day)
     */
  function dailyDataUpdate(uint256 beforeDay) external
  {
    GlobalsCache memory g;
    GlobalsCache memory gSnapshot;
    _globalsLoad(g, gSnapshot);

    if (beforeDay != 0) {
      require(beforeDay <= g._currentDay, "beforeDay cannot be in the future");

      _dailyDataUpdate(g, beforeDay, false);
    } else {
      /* Default to updating before current day */
      _dailyDataUpdate(g, g._currentDay, false);
    }

    _globalsSync(g, gSnapshot);
  }

  /**
   * @dev PUBLIC FACING: Helper to return multiple values of daily data with a single call.
     * @param beginDay First day of data range
     * @param endDay Last day (non-inclusive) of data range
     * @return list Fixed array of packed values
     */
  function dailyDataRange(uint256 beginDay, uint256 endDay) external view returns (uint256[] memory list)
  {
    require(beginDay < endDay && endDay <= globals.dailyDataCount, "range invalid");

    list = new uint256[](endDay - beginDay);

    uint256 src = beginDay;
    uint256 dst = 0;
    uint256 v;
    do {
      v = uint256(dailyData[src].dayUnclaimedSatoshisTotal) << (X_UINT_SIZE * 2);
      v |= uint256(dailyData[src].dayStakeSharesTotal) << X_UINT_SIZE;
      v |= uint256(dailyData[src].dayPayoutTotal);

      list[dst++] = v;
    }
    while (++src < endDay);

    return list;
  }

  /**
   * @dev PUBLIC FACING: External helper to return most global info with a single call.
     * @return Fixed array of values
     */
  function globalInfo() external view returns (uint256[9] memory) {
    return [
    // 1
    globals.lockedXsTotal,
    globals.nextStakeSharesTotal,
    globals.cdRate,
    globals.stakePenaltyTotal,
    // 2
    globals.dailyDataCount,
    globals.stakeSharesTotal,
    globals.latestStakeId,
    block.timestamp,
    bankXContract.totalSupply() / 1e10
    ];
  }

  /**
   * @dev PUBLIC FACING: ERC20 totalSupply() is the circulating supply and does not include any
     * staked Xs. allocatedSupply() includes both.
     * @return Allocated Supply in Xs
     */
  function allocatedSupply() external view returns (uint256){
    return bankXContract.totalSupply() / 1e10 + collateralPoolContract.bankx_minted_count() / 1e10 + globals.lockedXsTotal;
  }

  /**
   * @dev PUBLIC FACING: External helper for the current day number since launch time
     * @return Current day number (zero-based)
     */
  function currentDay() external view returns (uint256) {
    return _currentDay();
  }

  function _currentDay() internal view returns (uint256) {
    return (block.timestamp - launchTime) / 1 days;
  }

  function _dailyDataUpdateAuto(GlobalsCache memory g) internal {
    _dailyDataUpdate(g, g._currentDay, true);
  }

  function _globalsLoad(GlobalsCache memory g, GlobalsCache memory gSnapshot) internal view {
    // 1
    g._lockedXsTotal = globals.lockedXsTotal;
    g._nextStakeSharesTotal = globals.nextStakeSharesTotal;
    g._cdRate = globals.cdRate;
    g._stakePenaltyTotal = globals.stakePenaltyTotal;
    // 2
    g._dailyDataCount = globals.dailyDataCount;
    g._stakeSharesTotal = globals.stakeSharesTotal;
    g._latestStakeId = globals.latestStakeId;
    g._currentDay = _currentDay();

    _globalsCacheSnapshot(g, gSnapshot);
  }

  function _globalsCacheSnapshot(GlobalsCache memory g, GlobalsCache memory gSnapshot) internal pure
  {
    // 1
    gSnapshot._lockedXsTotal = g._lockedXsTotal;
    gSnapshot._nextStakeSharesTotal = g._nextStakeSharesTotal;
    gSnapshot._cdRate = g._cdRate;
    gSnapshot._stakePenaltyTotal = g._stakePenaltyTotal;
    // 2
    gSnapshot._dailyDataCount = g._dailyDataCount;
    gSnapshot._stakeSharesTotal = g._stakeSharesTotal;
    gSnapshot._latestStakeId = g._latestStakeId;
  }

  function _globalsSync(GlobalsCache memory g, GlobalsCache memory gSnapshot) internal {
    if (g._lockedXsTotal != gSnapshot._lockedXsTotal
    || g._nextStakeSharesTotal != gSnapshot._nextStakeSharesTotal
    || g._cdRate != gSnapshot._cdRate
      || g._stakePenaltyTotal != gSnapshot._stakePenaltyTotal) {
      // 1
      globals.lockedXsTotal = uint72(g._lockedXsTotal);
      globals.nextStakeSharesTotal = uint72(g._nextStakeSharesTotal);
      globals.cdRate = uint40(g._cdRate);
      globals.stakePenaltyTotal = uint72(g._stakePenaltyTotal);
    }
    if (g._dailyDataCount != gSnapshot._dailyDataCount
    || g._stakeSharesTotal != gSnapshot._stakeSharesTotal
      || g._latestStakeId != gSnapshot._latestStakeId) {
      // 2
      globals.dailyDataCount = uint16(g._dailyDataCount);
      globals.stakeSharesTotal = uint72(g._stakeSharesTotal);
      globals.latestStakeId = g._latestStakeId;
    }
  }

  function _stakeLoad(StakeStore storage stRef, uint40 stakeIdParam, StakeCache memory st) internal view
  {
    /* Ensure caller's stakeIndex is still current */
    require(stakeIdParam == stRef.stakeId, "stakeIdParam not in stake");

    st._stakeId = stRef.stakeId;
    st._stakedXs = stRef.stakedXs;
    st._stakeShares = stRef.stakeShares;
    st._lockedDay = stRef.lockedDay;
    st._stakedDays = stRef.stakedDays;
    st._unlockedDay = stRef.unlockedDay;
  }

  function _stakeUpdate(StakeStore storage stRef, StakeCache memory st) internal
  {
    stRef.stakeId = st._stakeId;
    stRef.stakedXs = uint72(st._stakedXs);
    stRef.stakeShares = uint72(st._stakeShares);
    stRef.lockedDay = uint16(st._lockedDay);
    stRef.stakedDays = uint16(st._stakedDays);
    stRef.unlockedDay = uint16(st._unlockedDay);
  }

  function _stakeAdd(
    StakeStore[] storage stakeListRef,
    uint40 newStakeId,
    uint256 newStakedXs,
    uint256 newStakeShares,
    uint256 newLockedDay,
    uint256 newStakedDays
  )
  internal
  {
    stakeListRef.push(
      StakeStore(
        newStakeId,
        uint72(newStakedXs),
        uint72(newStakeShares),
        uint16(newLockedDay),
        uint16(newStakedDays),
        uint16(0) // unlockedDay
      )
    );
  }

  /**
   * @dev Efficiently delete from an unordered array by moving the last element
     * to the "hole" and reducing the array length. Can change the order of the list
     * and invalidate previously held indexes.
     * @notice stakeListRef length and stakeIndex are already ensured valid in stakeEnd()
     * @param stakeListRef Reference to stakeLists[stakerAddr] array in storage
     * @param stakeIndex Index of the element to delete
     */
  function _stakeRemove(StakeStore[] storage stakeListRef, uint256 stakeIndex) internal
  {
    uint256 lastIndex = stakeListRef.length - 1;

    /* Skip the copy if element to be removed is already the last element */
    if (stakeIndex != lastIndex) {
      /* Copy last element to the requested element's "hole" */
      stakeListRef[stakeIndex] = stakeListRef[lastIndex];
    }

    /*
        Reduce the array length now that the array is contiguous.
        Surprisingly, 'pop()' uses less gas than 'stakeListRef.length = lastIndex'
    */
    stakeListRef.pop();
  }

  /**
   * @dev Estimate the stake payout for an incomplete day
     * @param g Cache of stored globals
     * @param stakeSharesParam Param from stake to calculate bonuses for
     * @param day Day to calculate bonuses for
     * @return payout Payout in Xs
     */
  function _estimatePayoutRewardsDay(GlobalsCache memory g, uint256 stakeSharesParam, uint256 day)
  internal view returns (uint256 payout)
  {
    /* Prevent updating state for this estimation */
    GlobalsCache memory gTmp;
    _globalsCacheSnapshot(g, gTmp);

    DailyRoundState memory rs;
    rs._allocSupplyCached = bankXContract.totalSupply() / 1e10 + g._lockedXsTotal;

    _dailyRoundCalc(gTmp, rs, day);

    /* Stake is no longer locked so it must be added to total as if it were */
    gTmp._stakeSharesTotal += stakeSharesParam;

    payout = rs._payoutTotal * stakeSharesParam / gTmp._stakeSharesTotal;

    return payout;
  }

  function _dailyRoundCalc(GlobalsCache memory g, DailyRoundState memory rs, uint256 day) private pure
  {
    /*
        Calculate payout round

        Inflation of 5.28% inflation per 364 days             (approx 1 year)
        dailyInterestRate   = exp(log(1 + 5.28%)  / 364) - 1
                            = exp(log(1 + 0.0528) / 364) - 1
                            = exp(log(1.0528) / 364) - 1
                            = 0.000141365                     (approx)

        payout  = allocSupply * dailyInterestRate
                = allocSupply / (1 / dailyInterestRate)
                = allocSupply / (1 / 0.000141365)
                = allocSupply / 7073.88674707                 (approx)
                = allocSupply * 10000 / 70738867              (* 10000/10000 for int precision)
    */

    rs._payoutTotal = rs._allocSupplyCached * 10000 / 70738867;

    if (g._stakePenaltyTotal != 0) {
      rs._payoutTotal += g._stakePenaltyTotal;
      g._stakePenaltyTotal = 0;
    }
  }

  function _dailyRoundCalcAndStore(GlobalsCache memory g, DailyRoundState memory rs, uint256 day) private
  {
    _dailyRoundCalc(g, rs, day);

    dailyData[day].dayPayoutTotal = uint72(rs._payoutTotal);
    dailyData[day].dayStakeSharesTotal = uint72(g._stakeSharesTotal);
  }

  function _dailyDataUpdate(GlobalsCache memory g, uint256 beforeDay, bool isAutoUpdate) private
  {
    if (g._dailyDataCount >= beforeDay) {
      /* Already up-to-date */
      return;
    }

    DailyRoundState memory rs;
    rs._allocSupplyCached = bankXContract.totalSupply() / 1e10 + g._lockedXsTotal;

    uint256 day = g._dailyDataCount;

    _dailyRoundCalcAndStore(g, rs, day);

    /* Stakes started during this day are added to the total the next day */
    if (g._nextStakeSharesTotal != 0) {
      g._stakeSharesTotal += g._nextStakeSharesTotal;
      g._nextStakeSharesTotal = 0;
    }

    while (++day < beforeDay) {
      _dailyRoundCalcAndStore(g, rs, day);
    }

    _emitDailyDataUpdate(g._dailyDataCount, day, isAutoUpdate);
    g._dailyDataCount = day;

    if (rs._mintOriginBatch != 0) {
      bankXContract.pool_mint(ORIGIN_ADDR, rs._mintOriginBatch * 1e10);
    }
  }

  function _emitDailyDataUpdate(uint256 beginDay, uint256 endDay, bool isAutoUpdate) private
  {
    emit DailyDataUpdate(
      uint256(uint40(block.timestamp))
      | (uint256(uint16(beginDay)) << 40)
      | (uint256(uint16(endDay)) << 56)
      | (isAutoUpdate ? (1 << 72) : 0),
      msg.sender
    );
  }

  function updateBankXContract(address _bankXContract) public onlyOwner() {
    bankXContract = BankXInterface(_bankXContract);
  }

  function updateNFTBonusContract(address _nftBonusContract) public onlyOwner() {
    nftBonusContract = NFTBonusInterface(_nftBonusContract);
  }

  function updateCollateralPoolContract(address _collateralPoolContract) public onlyOwner() {
    collateralPoolContract = CollateralPoolInterface(_collateralPoolContract);
  }
}
