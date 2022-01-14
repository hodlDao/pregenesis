pragma solidity ^0.5.16;


import "./openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./openzeppelin/contracts/ownership/Ownable.sol";


// WaspToken
contract LpToken is ERC20, Ownable {
    string public name;
    uint8 public decimal;

    constructor(string memory _name,uint8 _decimal) public {
        name = _name;
        decimal = _decimal;
    }

    function decimals() public view returns (uint8) {
        return decimal;
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (WanSwapFarm).
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    address public token0;
    address public token1;
    function setReserve(address _token0, address _token1) public {
        token0 = _token0;
        token1 = _token1;
    }
}