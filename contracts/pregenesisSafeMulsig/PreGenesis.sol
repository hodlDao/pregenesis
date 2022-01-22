// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.5.16;

import "../modules/SafeMath.sol";
import "../modules/proxyOwner.sol";
import "../modules/IERC20.sol";
import "../modules/SafeERC20.sol";
import "../pregenesis/PreGenesisData.sol";

contract PreGenesisWithSafe is PreGenesisData{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public safeMulsig;

    modifier onlySafeMulsig() {
        require(msg.sender==safeMulsig, "not setting safe contract");
        _;
    }

    constructor (address _safeMulsig)
        public
    {
        safeMulsig = _safeMulsig;
        allowWithdraw = false;
        allowDeposit = false;
    }

    function initContract(uint256 _interestRate,uint256 _interestInterval,
        uint256 _assetCeiling,uint256 _assetFloor) external onlySafeMulsig{

        assetCeiling = _assetCeiling;
        assetFloor = _assetFloor;
        _setInterestInfo(_interestRate,_interestInterval,maxRate,rayDecimals);
        emit InitContract(msg.sender,_interestRate,_interestInterval,_assetCeiling,_assetFloor);
    }

    function setCoinAndTarget(address _coin,address _targetSc) external onlySafeMulsig {
        coin = _coin;
        targetSc = _targetSc;
    }

    function setPoolLimitation(uint256 _assetCeiling,uint256 _assetFloor) external onlySafeMulsig{
        assetCeiling = _assetCeiling;
        assetFloor = _assetFloor;
    }

    function setInterestInfo(uint256 _interestRate,uint256 _interestInterval)external onlySafeMulsig{
        _setInterestInfo(_interestRate,_interestInterval,maxRate,rayDecimals);
    }

    function setWithdrawStatus(bool _enable)external onlySafeMulsig{
       allowWithdraw = _enable;
    }

    function setDepositStatus(bool _enable)external onlySafeMulsig{
        allowDeposit = _enable;
    }

    function deposit(uint256 amount)
        notHalted
        nonReentrant
        settleAccount(msg.sender)
        external
    {
        require(allowDeposit,"deposit is not allowed!");
        require(totalAssetAmount < assetCeiling, "asset is overflow");

        if(totalAssetAmount.add(amount)>assetCeiling) {
            amount = assetCeiling.sub(totalAssetAmount);
        }
        IERC20(coin).safeTransferFrom(msg.sender, address(this), amount);

        assetInfoMap[msg.sender].originAsset = assetInfoMap[msg.sender].originAsset.add(amount);
        assetInfoMap[msg.sender].assetAndInterest = assetInfoMap[msg.sender].assetAndInterest.add(amount);
        totalAssetAmount = totalAssetAmount.add(amount);

        emit Deposit(msg.sender,msg.sender,amount);
    }

    function transferVCoin(address _user,uint256 _vCoinAmount)
        notHalted
        nonReentrant
        settleAccount(targetSc)
        settleAccount(_user)
        external
    {
        require(msg.sender==targetSc,"wrong sender");

        assetInfoMap[_user].assetAndInterest = assetInfoMap[_user].assetAndInterest.sub(_vCoinAmount);
        assetInfoMap[targetSc].assetAndInterest = assetInfoMap[targetSc].assetAndInterest.add(_vCoinAmount);

        assetInfoMap[_user].finalAsset =  assetInfoMap[_user].finalAsset.add(_vCoinAmount);
        emit TransferToTarget(_user,targetSc,_vCoinAmount);
    }

    function withdraw()
         notHalted
         nonReentrant
         settleAccount(msg.sender)
         external
    {
        require(allowWithdraw,"withdraw is not allowed!");

        uint256 amount = assetInfoMap[msg.sender].originAsset;
        assetInfoMap[msg.sender].originAsset = 0;
        assetInfoMap[msg.sender].assetAndInterest = 0;
        IERC20(coin).safeTransfer(msg.sender, amount);
        emit Withdraw(coin,msg.sender,amount);
    }

    function TransferCoinToTarget() public onlySafeMulsig {
        uint256 coinBal = IERC20(coin).balanceOf(address(this));
        IERC20(coin).safeTransfer(targetSc, coinBal);
        emit TransferToTarget(msg.sender,targetSc,coinBal);
    }

    function getUserBalanceInfo(address _user)public view returns(uint256,uint256,uint256){
        if(assetInfoMap[_user].interestRateOrigin == 0 || interestInterval == 0){
            return (0,0,0);
        }
        uint256 newRate = newAccumulatedRate();
        uint256 vcoin = assetInfoMap[_user].assetAndInterest.mul(newRate)/assetInfoMap[_user].interestRateOrigin;
        return (assetInfoMap[_user].originAsset,vcoin,assetInfoMap[_user].finalAsset);
    }

    function getInterestInfo()external view returns(uint256,uint256){
        return (interestRate,interestInterval);
    }

    function _setInterestInfo(uint256 _interestRate,uint256 _interestInterval,uint256 _maxRate,uint256 _minRate) internal {
        if (accumulatedRate == 0){
            accumulatedRate = rayDecimals;
        }
        require(_interestRate<=1e27,"input stability fee is too large");
        require(_interestInterval>0,"input mine Interval must larger than zero");
        uint256 newLimit = rpower(uint256(1e27+_interestRate),31536000/_interestInterval,rayDecimals);
        require(newLimit<= _maxRate && newLimit>= _minRate,"input rate is out of range");

        _interestSettlement();
        interestRate = _interestRate;
        interestInterval = _interestInterval;

        emit SetInterestInfo(msg.sender,_interestRate,_interestInterval);
    }


    function rpower(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                let xx := mul(x, x)
                if iszero(eq(div(xx, x), x)) { revert(0,0) }
                let xxRound := add(xx, half)
                if lt(xxRound, xx) { revert(0,0) }
                x := div(xxRound, base)
                if mod(n,2) {
                    let zx := mul(z, x)
                    if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                    let zxRound := add(zx, half)
                    if lt(zxRound, zx) { revert(0,0) }
                    z := div(zxRound, base)
                }
            }
            }
        }
    }

    function _interestSettlement()internal{
        uint256 _interestInterval = interestInterval;
        if (_interestInterval>0){
            uint256 newRate = newAccumulatedRate();
            //totalAssetAmount = totalAssetAmount.mul(newRate)/accumulatedRate;
            accumulatedRate = newRate;
            latestSettleTime = currentTime()/_interestInterval*_interestInterval;
        }else{
            latestSettleTime = currentTime();
        }
    }

    function newAccumulatedRate() internal view returns (uint256){
        uint256 newRate = rpower(uint256(1e27+interestRate),(currentTime()-latestSettleTime)/interestInterval,rayDecimals);
        return accumulatedRate.mul(newRate)/rayDecimals;
    }

    function settleUserInterest(address account)internal{
        assetInfoMap[account].assetAndInterest = _settlement(account);
        assetInfoMap[account].interestRateOrigin = accumulatedRate;
    }

    function _settlement(address account) internal view returns (uint256) {
        if (assetInfoMap[account].interestRateOrigin == 0){
            return 0;
        }
        return assetInfoMap[account].assetAndInterest.mul(accumulatedRate)/assetInfoMap[account].interestRateOrigin;
    }

    modifier settleAccount(address account){
        _interestSettlement();
        settleUserInterest(account);
        _;
    }
    
    function currentTime() internal view returns (uint256){
        return block.timestamp;
    }
}