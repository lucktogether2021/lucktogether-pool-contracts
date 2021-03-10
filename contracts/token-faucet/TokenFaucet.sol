// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/ExtendedSafeCast.sol";
import "../token/TokenListener.sol";

/// @title Disburses a token at a fixed rate per second to holders of another token.
/// @notice The tokens are dripped at a "drip rate per second".  This is the number of tokens that
/// are dripped each second.  A user's share of the dripped tokens is based on how many 'measure' tokens they hold.
/* solium-disable security/no-block-members */

interface IDripRatePerSecondAttenuationStrategy{
  function calculateDripRatePerSecond(uint256 dripRatePerSecond,uint256 cycleCount,uint256 attenuationCoefficient) external pure returns(uint256);
}

interface IMeasure{
  function getAllShares() external view returns (uint256);
  function getUserAssets(address user) external view returns (uint256);
}


contract TokenFaucet is OwnableUpgradeable, TokenListener {
  using SafeMathUpgradeable for uint256;
  using SafeCastUpgradeable for uint256;
  using ExtendedSafeCast for uint256;  

  event Initialized(
    IERC20Upgradeable indexed asset,
    FaucetInit[] faucetInits
  );

  event Dripped(
    address indexed ticket,
    uint256 newTokens
  );

  event Deposited(
    address indexed user,
    uint256 amount
  );

  event Claimed(
    address indexed user,
    uint256 newTokens
  );

  event DripRateChanged(
    address measure,
    uint256 dripRatePerSecond
  );

  event DripRateAttenuationCoefficientChanged(
    address measure,
    uint256 dripRatePerSecondAttenuation
  );

  event DripRateAttenuationStrategyChanged(
    address measure,
    address dripRatePerSecondAttenuationStrategy
  );

  struct UserState {
    uint128 lastExchangeRateMantissa;
    uint128 balance;
  }
  
  struct FaucetInit {
    address measure;
    uint256 dripRatePerSecond;    
    address dripRatePerSecondAttenuationStrategy;  
      
  }
  
  struct Faucet {
    address measure;
    uint112 totalUnclaimed;
    uint112 exchangeRateMantissa;
    uint256 dripRatePerSecond;
    uint256 attenuationCoefficient;
    address dripRatePerSecondAttenuationStrategy;
    uint256 lastDripTimestamp;
    uint256 lasTattenuationTimestamp;
    mapping(address => UserState) userStates;
    
  }

  /// @notice The token that is being disbursed
  IERC20Upgradeable public asset;
  
  /// @notice The total amount of tokens that have been dripped but not claimed
  uint112 public totalUnclaimed;
  
  /// @notice Attenuation cycle 90 Days
  uint256 public attenuationCycle = 90 days;

  /// @notice Attenuation coefficient
  uint256 public attenuationCoefficient = 0.0110e18;
  
   /// @notice The data structure that faucets
  mapping(address => Faucet) public faucets;

  /// @notice Initializes a new Comptroller V2
  /// @param _asset The asset to disburse to users
  function initialize (
    IERC20Upgradeable _asset,
    FaucetInit[] memory faucetInits
  ) public initializer {
    __Ownable_init();
    asset = _asset;
    // @notice set faucets
    for (uint i = 0; i < faucetInits.length; i ++) {
      FaucetInit memory faucetInit = faucetInits[i];
      _addFaucet(faucetInit);
    }
    
    emit Initialized(asset, faucetInits);
    
    
  }

  function getUserStates(address measure, address user) external view returns(UserState memory) {
    return faucets[measure].userStates[user];
  }
  
  /// @notice addFaucet
  function addFaucet(FaucetInit memory faucetInit) external onlyOwner{
       _addFaucet(faucetInit);
  }
  
  /// @notice addFaucet
  function _addFaucet(FaucetInit memory faucetInit) private {
      address _measure = faucetInit.measure;
      uint256 _dripRatePerSecond = faucetInit.dripRatePerSecond;
      uint256 _attenuationCoefficient = attenuationCoefficient;
      address _dripRatePerSecondAttenuationStrategy = faucetInit.dripRatePerSecondAttenuationStrategy;
      uint256 _currentTime = _currentTime();
      faucets[_measure] = Faucet({
           measure:_measure,
           totalUnclaimed : 0,
           exchangeRateMantissa : 0,
           dripRatePerSecond : _dripRatePerSecond,
           dripRatePerSecondAttenuationStrategy:_dripRatePerSecondAttenuationStrategy,
           attenuationCoefficient : _attenuationCoefficient,
           lastDripTimestamp:_currentTime,
           lasTattenuationTimestamp :_currentTime
      });
     setDripRatePerSecond(_dripRatePerSecond,faucetInit.measure);
  }
  
  /// @notice Safely deposits asset tokens into the faucet.  Must be pre-approved
  /// This should be used instead of transferring directly because the drip function must
  /// be called before receiving new assets.
  /// @param amount The amount of asset tokens to add (must be approved already)
  function deposit(uint256 amount,address measure) external {
    drip(measure);
    asset.transferFrom(msg.sender, address(this), amount);

    emit Deposited(msg.sender, amount);
  }

  /// @notice Transfers all unclaimed tokens to the user
  /// @param user The user to claim tokens for
  /// @return The amount of tokens that were claimed.
  function _claim(address user,address measure) internal returns (uint256) {
    drip(measure);
    _captureNewTokensForUser(measure, user);
    uint256 balance = faucets[measure].userStates[user].balance;
    faucets[measure].totalUnclaimed = uint256(faucets[measure].totalUnclaimed).sub(balance).toUint112();
    totalUnclaimed = uint256(totalUnclaimed).sub(balance).toUint112();
    asset.transfer(user, balance);
    emit Claimed(user, balance);
    faucets[measure].userStates[user].balance = 0;
    return balance;
  }

  function claim(address user,address measure) external returns (uint256){
    return _claim(user, measure);
  }
  
  /// @notice Runs claim on all passed measures for a user.
  /// @param user The user to claim for
  /// @param measures The measures to call claim on.
  function claimAll(address user, address[] calldata measures) external {
    for (uint256 i = 0; i < measures.length; i++) {
      _claim(user, measures[i]);
    }
  }

  /// @notice Drips new tokens.
  /// @dev Should be called immediately before any measure token mints/transfers/burns
  /// @return The number of new tokens dripped.
  function drip(address measure) public returns (uint256) {
    uint256 currentTimestamp = _currentTime();
    Faucet memory faucet = faucets[measure];

    // this should only run once per block.
    if (faucet.lastDripTimestamp == uint32(currentTimestamp)) {
      return 0;
    }
    
    uint256 newSecondsDrip = currentTimestamp.sub(faucet.lastDripTimestamp);
    uint256 newSecondsAttenuation = currentTimestamp.sub(faucet.lasTattenuationTimestamp);

    // upData dripRatePerSecond
    uint cycleCount = newSecondsAttenuation.div(attenuationCycle);
    if(cycleCount >= 1){
      // calculate dripRatePerSecond
      uint256 calculateDripRatePerSecond = IDripRatePerSecondAttenuationStrategy(faucet.dripRatePerSecondAttenuationStrategy)
          .calculateDripRatePerSecond(faucet.dripRatePerSecond,cycleCount,faucet.attenuationCoefficient);  

      if(faucet.dripRatePerSecond != calculateDripRatePerSecond){
         faucets[measure].dripRatePerSecond = calculateDripRatePerSecond;
         faucets[measure].lasTattenuationTimestamp = faucet.lasTattenuationTimestamp.add(cycleCount.mul(attenuationCycle));
      }
     
    } 

    uint256 assetTotalSupply = asset.balanceOf(address(this));
    uint256 availableTotalSupply = assetTotalSupply.sub(totalUnclaimed);
    uint256 nextExchangeRateMantissa = faucet.exchangeRateMantissa;
    uint256 newTokens;
    uint256 measureTotalSupply = IMeasure(measure).getAllShares();

    if (measureTotalSupply > 0 && availableTotalSupply > 0) {
      newTokens = newSecondsDrip.mul(faucet.dripRatePerSecond);
      if (newTokens > availableTotalSupply) {
        newTokens = availableTotalSupply;
      }
      uint256 indexDeltaMantissa = FixedPoint.calculateMantissa(newTokens, measureTotalSupply);
      nextExchangeRateMantissa = nextExchangeRateMantissa.add(indexDeltaMantissa);

      emit Dripped(
        measure,  
        newTokens
      );
    }

    faucets[measure].exchangeRateMantissa = nextExchangeRateMantissa.toUint112();
    totalUnclaimed = uint256(totalUnclaimed).add(newTokens).toUint112();
    faucets[measure].totalUnclaimed = uint256(faucet.totalUnclaimed).add(newTokens).toUint112();
    faucets[measure].lastDripTimestamp = currentTimestamp.toUint32();

    return newTokens;
  }

  function setDripRatePerSecond(uint256 _dripRatePerSecond,address measure) public onlyOwner {
    require(_dripRatePerSecond > 0, "TokenFaucet/dripRate-gt-zero");
   
    // ensure we're all caught up
    drip(measure);
    Faucet memory faucet = faucets[measure];
    // updata attenuationCoefficient 
    // dripRatePerSecond/attenuationCoefficient = _dripRatePerSecond/x
    if(faucet.dripRatePerSecond > 0){
      faucets[measure].attenuationCoefficient  = _dripRatePerSecond.mul(faucet.attenuationCoefficient).div(faucet.dripRatePerSecond);
    }
  
    faucets[measure].dripRatePerSecond = _dripRatePerSecond;

    emit DripRateChanged(measure,_dripRatePerSecond);
  }

  /// @notice Set DripRate Attenuation Coefficient
  function setDripRateAttenuationCoefficient(address measure,uint256 _coefficient) public onlyOwner {
    faucets[measure].attenuationCoefficient = _coefficient;

    emit DripRateAttenuationCoefficientChanged(measure,_coefficient);
  }
  
  /// @notice Set DripRate Attenuation Strategy
  function setDripRateAttenuationStrategy(address measure,address _strategy ) public onlyOwner {
    faucets[measure].dripRatePerSecondAttenuationStrategy = _strategy;

    emit DripRateAttenuationStrategyChanged(measure,_strategy);
    
  }

  /// @notice Captures new tokens for a user
  /// @dev This must be called before changes to the user's balance (i.e. before mint, transfer or burns)
  /// @param user The user to capture tokens for
  /// @return The number of new tokens
  function _captureNewTokensForUser(
    address measure,
    address user
  ) private returns (uint128) {
    Faucet storage faucet = faucets[measure];  
    UserState memory userState = faucet.userStates[user];
    if (faucet.exchangeRateMantissa == userState.lastExchangeRateMantissa) {
      // ignore if exchange rate is same
      return 0;
    }
    uint256 deltaExchangeRateMantissa = uint256(faucet.exchangeRateMantissa).sub(userState.lastExchangeRateMantissa);
    uint256 userMeasureBalance = IMeasure(measure).getUserAssets(user);
    uint128 newTokens = FixedPoint.multiplyUintByMantissa(userMeasureBalance, deltaExchangeRateMantissa).toUint128();

    faucets[measure].userStates[user] = UserState({
      lastExchangeRateMantissa: faucet.exchangeRateMantissa,
      balance: uint256(userState.balance).add(newTokens).toUint128()
    });

    return newTokens;
  }

  /// @notice Should be called before a user mints new "measure" tokens.
  /// @param to The user who is minting the tokens
  /// @param token The token they are minting
  function beforeTokenMint(
    address to,
    uint256,
    address token,
    address
  )
    external
    override
  {
    Faucet memory faucet = faucets[token];
    address measure = faucet.measure;  
    if (measure != address(0)) {
      drip(measure);
      _captureNewTokensForUser(measure,to);
    }
  }

  /// @notice Should be called before "measure" tokens are transferred or burned
  /// @param from The user who is sending the tokens
  /// @param to The user who is receiving the tokens
  /// @param token The token token they are burning
  function beforeTokenTransfer(
    address from,
    address to,
    uint256,
    address token
  )
    external
    override
  {
    Faucet memory faucet = faucets[token];
    address measure = faucet.measure;
    // must be measure and not be minting
    if (measure != address(0) && from != address(0)) {
      drip(measure);
      _captureNewTokensForUser(measure,to);
      _captureNewTokensForUser(measure,from);
    }
  }

  /// @notice returns the current time.  Allows for override in testing.
  /// @return The current time (block.timestamp)
  function _currentTime() internal virtual view returns (uint32) {
    return block.timestamp.toUint32();
  }

}
