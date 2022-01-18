interface IPregenesis {
    function transferVCoin(address _user,uint256 _vCoinAmount) external;
    function getUserBalanceInfo(address _user) external view returns(uint256,uint256,uint256);
}
// WaspToken
contract MockGenesisCall is Ownable {
    address public pregenesis;


    constructor() public {
    }

    function setPregenesis(address _pregenesis) public {
       pregenesis = _pregenesis;
    }

    function getUserBalanceInfo(address _user) external view returns(uint256){
        uint256 vUsdcBal;
        (,vUsdcBal,) = IPregenesis(pregenesis).getUserBalanceInfo(_user);
        return vUsdcBal;
    }

    function transferVcoinFromPregenesis() public {
        uint256 vUsdcBal;
        (,vUsdcBal,) = IPregenesis(pregenesis).getUserBalanceInfo(msg.sender);
        IPregenesis(pregenesis).transferVCoin(msg.sender,vUsdcBal);
    }


}