// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.5.16;

import "../modules/SafeMath.sol";
import "../modules/proxyOwner.sol";
import "../modules/IERC20.sol";
import "../modules/SafeERC20.sol";
import "./PreGenesisData.sol";

contract PreGenesis is PreGenesisData,proxyOwner{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor (address _multiSignature,
                 address _origin0,
                 address _origin1
                )
        proxyOwner(_multiSignature, _origin0, _origin1)
        public
    {
        allowWithdraw = false;
        allowDeposit = false;
    }

    function initContract(uint256 _interestRate,uint256 _interestInterval,
        uint256 _assetCeiling,uint256 _assetFloor,address _coin,address _targetSc) external onlyOrigin{

        assetCeiling = _assetCeiling;
        assetFloor = _assetFloor;
        _setInterestInfo(_interestRate,_interestInterval,maxRate,rayDecimals);

        coin = _coin;
        targetSc = _targetSc;

        emit InitContract(msg.sender,_interestRate,_interestInterval,_assetCeiling,_assetFloor);
    }

    function setCoinAndTarget(address _coin,address _targetSc) public onlyOrigin {
        coin = _coin;
        targetSc = _targetSc;
    }

    function setPoolLimitation(uint256 _assetCeiling,uint256 _assetFloor) external onlyOrigin{
        assetCeiling = _assetCeiling;
        assetFloor = _assetFloor;
    }

    function setInterestInfo(uint256 _interestRate,uint256 _interestInterval)external onlyOrigin{
        _setInterestInfo(_interestRate,_interestInterval,maxRate,rayDecimals);
    }

    function setWithdrawStatus(bool _enable)external onlyOrigin{
       allowWithdraw = _enable;
    }

    function setDepositStatus(bool _enable)external onlyOrigin{
        allowDeposit = _enable;
    }

    function setHalt(bool halt)
        public
        onlyOrigin
    {
        halted = halt;
    }

    function deposit(uint256 amount)
        notHalted
        nonReentrant
        external
    {
        require(allowDeposit,"deposit is not allowed!");
        require(totalAssetAmount < assetCeiling, "asset is overflow");

        if(totalAssetAmount.add(amount)>assetCeiling) {
            amount = assetCeiling.sub(totalAssetAmount);
        }
        IERC20(coin).safeTransferFrom(msg.sender, address(this), amount);

        _interestSettlement();

        //user current vcoin amount + coin amount
        uint256 newAmount =  calBaseAmount(amount,accumulatedRate);
        assetInfoMap[msg.sender].baseAsset = assetInfoMap[msg.sender].baseAsset.add(newAmount);

        assetInfoMap[msg.sender].originAsset = assetInfoMap[msg.sender].originAsset.add(amount);
        totalAssetAmount = totalAssetAmount.add(amount);

        emit Deposit(msg.sender,msg.sender,amount);
    }

    function transferVCoin(address _user,uint256 _vCoinAmount)
        notHalted
        nonReentrant
        external
    {
        require(msg.sender==targetSc,"wrong sender");

        _interestSettlement();

        uint256 assetAndInterest = getAssetBalance(_user);
        uint256 burnAmount = calBaseAmount(_vCoinAmount,accumulatedRate);

        if(assetAndInterest <= _vCoinAmount){
            assetInfoMap[_user].baseAsset = 0;
        }else if(assetAndInterest > _vCoinAmount){
            assetInfoMap[_user].baseAsset = assetInfoMap[_user].baseAsset.sub(burnAmount);
        }

        //tartget sc only record vcoin balance,no interest
        assetInfoMap[targetSc].baseAsset = assetInfoMap[targetSc].baseAsset.add(burnAmount);

        //record how many vcoind is transfer to targetSc
        assetInfoMap[_user].finalAsset =  assetInfoMap[_user].finalAsset.add(_vCoinAmount);

        emit TransferVCoinToTarget(_user,targetSc,_vCoinAmount);
    }

    //only transfer user's usdc coin if allowed to withdraw
    function withdraw()
         notHalted
         nonReentrant
         external
    {
        require(allowWithdraw,"withdraw is not allowed!");

        uint256 amount = assetInfoMap[msg.sender].originAsset;
        assetInfoMap[msg.sender].originAsset = 0;
        assetInfoMap[msg.sender].baseAsset = 0;
        IERC20(coin).safeTransfer(msg.sender, amount);
        emit Withdraw(coin,msg.sender,amount);
    }

    //transfer usdc coin in sc to target sc if multisig permit
    function TransferCoinToTarget() public onlyOrigin {
        uint256 coinBal = IERC20(coin).balanceOf(address(this));
        IERC20(coin).safeTransfer(targetSc, coinBal);
        emit TransferToTarget(msg.sender,targetSc,coinBal);
    }

    function getUserBalanceInfo(address _user)public view returns(uint256,uint256,uint256){
        if(interestInterval == 0){
            return (0,0,0);
        }
        uint256 vAsset = getAssetBalance(_user);
        return (assetInfoMap[_user].originAsset,vAsset,assetInfoMap[_user].finalAsset);
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

    function getAssetBalance(address account)public view returns(uint256){
        return calInterestAmount(assetInfoMap[account].baseAsset,newAccumulatedRate());
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

//    modifier settleInterest(){
//        _interestSettlement();
//        _;
//    }
    /**
     * @dev the auxiliary function for _mineSettlementAll.
     */
    function _interestSettlement()internal{
        uint256 _interestInterval = interestInterval;
        if (_interestInterval>0){
            accumulatedRate = newAccumulatedRate();
            latestSettleTime = currentTime()/_interestInterval*_interestInterval;
        }else{
            latestSettleTime = currentTime();
        }
    }

    function newAccumulatedRate()internal  view returns (uint256){
        uint256 newRate = rpower(uint256(rayDecimals+interestRate),(currentTime()-latestSettleTime)/interestInterval,rayDecimals);
        return accumulatedRate.mul(newRate)/rayDecimals;
    }

    function currentTime() internal view returns (uint256){
        return block.timestamp;
    }

    function calBaseAmount(uint256 amount, uint256 _interestRate) internal pure returns(uint256){
        return amount.mul(InterestDecimals)/_interestRate;
    }

    function calInterestAmount(uint256 amount, uint256 _interestRate) internal pure returns(uint256){
        return amount.mul(_interestRate)/InterestDecimals;
    }

}