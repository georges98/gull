// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./SafeMath.sol";

contract GullToken is ERC20,Ownable,AccessControl {
    using SafeMath for uint256;
    struct CappedWithdrawal {
        uint256 time;
        uint256 amount;
    }
    
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) private _isExcludedFromCap;
    mapping (address => CappedWithdrawal) private _cappedWithdrawalArray;
    mapping (address => bool) public automatedMarketMakerPairs;

    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Pair public immutable pair;
    address private developer = address(0x8a1BCa617F34Cf10b8C08b765CAC7922dB5Da8EB);
    address private community = address(0x8a1BCa617F34Cf10b8C08b765CAC7922dB5Da8EB);
    address private liquidity = address(0x8a1BCa617F34Cf10b8C08b765CAC7922dB5Da8EB);
    bool private swapping = false;

    bool private enableSwap   = true;
    bool private enableTaxFee = true;
    bool private enablecappedWithdrawalLimit = true;
    
    uint256 public constant CAPPED_SUPPLY = 150000000 * (10**18);
    // transfer fees
    uint256 public devFee = 6;
    uint256 public communityFee = 2;
    uint256 public liquidityFee = 2;
    uint256 public swapTokensAtAmount = 1000 * (10**18);

    uint256 public cappedWithdrawalLimit = 20000 * (10**18); // 20000 $GULL per determined time
    uint256 public cappedWithdrawalTimeSpan = 1 days; // 20000 $GULL per 1 day
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    constructor() ERC20("Gull", "GULL") {


       IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
      //  Create a uniswap pair for this new token
       address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this),_uniswapV2Router.WETH());

         // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
        pair = IUniswapV2Pair(_uniswapV2Pair);
    
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
        excludeFromFees(developer, true);
        excludeFromFees(community, true);
        excludeFromFees(liquidity, true);

        excludeFromCap(address(this), true);
        excludeFromCap(address(_uniswapV2Router), true);
        excludeFromCap(owner(), true);
        excludeFromCap(_uniswapV2Pair, true);
        excludeFromCap(developer, true);
        excludeFromCap(community, true);
        excludeFromCap(liquidity, true);
        

        setAutomatedMarketMakerPair(_uniswapV2Pair, true);
        setAutomatedMarketMakerPair(address(uniswapV2Router), true);

        _mint(owner(), 13200000 * (10**18));
    }

    receive() external payable{

    }

    function mint(address to, uint amount) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(CAPPED_SUPPLY >= amount+totalSupply(), "Exceeded the capped amount");

        _mint(to, amount);
    }

    function burn(address account, uint amount) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");

        _burn(account, amount);
    }

    function addAdminRole(address admin) public{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");

        _setupRole(ADMIN_ROLE, admin);
    }

    function revokeAdminRole(address admin) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");

        revokeRole(ADMIN_ROLE, admin);
    }

    function adminRole(address admin) public view returns(bool){
        return hasRole(ADMIN_ROLE,admin);
    }
    
    function updateCappedWithdrawal(uint256 _cappedWithdrawalLimit) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(_cappedWithdrawalLimit >= (1000 * (10**18)), "1k is the min amount");
        cappedWithdrawalLimit = _cappedWithdrawalLimit;
    }  

    function updateCappedWithdrawalTime(uint256 _cappedWithdrawalTimeSpan) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(_cappedWithdrawalTimeSpan <= 3 days, "3 days is the max time");
        cappedWithdrawalTimeSpan = _cappedWithdrawalTimeSpan;
    }

    function excludeFromFees(address account, bool excluded) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        _isExcludedFromFees[account] = excluded;
    } 

     function setAutomatedMarketMakerPair(address account, bool value) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        automatedMarketMakerPairs[account] = value;
    }
 

    function excludeFromCap(address account, bool excluded) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        _isExcludedFromCap[account] = excluded;
    }   

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function isExcludedFromCap(address account) public view returns(bool) {
        return _isExcludedFromCap[account];
    }
   
    function _transferOwnership(address newOwner) public onlyOwner {
        transferOwnership(newOwner);
    }

    function _transferFeesWallets(address newOwnerDev,address newOwnerCom,address newOwnerLiq) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        developer = newOwnerDev;
        community = newOwnerCom;
        liquidity = newOwnerLiq;

        excludeFromCap(newOwnerDev, true);
        excludeFromCap(newOwnerCom, true);
        excludeFromCap(newOwnerLiq, true);
        
        excludeFromFees(newOwnerDev, true);
        excludeFromFees(newOwnerCom, true);
        excludeFromFees(newOwnerLiq, true);
    }

    function updateCappedWithdrawalToggle(bool _enablecappedWithdrawalLimit) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        enablecappedWithdrawalLimit = _enablecappedWithdrawalLimit;
    }

    function updateSwapTokenAmount(uint256 _swapTokensAtAmount) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        swapTokensAtAmount = _swapTokensAtAmount;
    }

    function updateSwapToggle(bool _enableSwap) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        enableSwap = _enableSwap;
    }

    function updateFeesToggle(bool _enableTaxFee) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        enableTaxFee = _enableTaxFee;
    }
 
    function updateFees(uint256 _devFee, uint256 _communityFee,uint256 _liquidityFee) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        devFee = _devFee;
        communityFee = _communityFee;
        liquidityFee = _liquidityFee;
    }

    function updateUniswapV2Router(address newAddress) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        uniswapV2Router = IUniswapV2Router02(newAddress);
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
    }

    function _transfer(address from,address to, uint256 amount) internal override {
       require(acceptWithdraw(from,amount), "You exceeded the limit");
       require(to != address(0), "Address should not be 0");
       require(amount > 0, "Amount should be greater than 0");

       uint256 newAmount = amount;
       //tax fee calculation
       if(!(_isExcludedFromFees[from] || _isExcludedFromFees[to]) && enableTaxFee && !swapping)
        {
            newAmount = _partialFee(from,amount);
        }

        super._transfer(from,to,newAmount);
    }

    function acceptWithdraw(address from,uint256 amount) internal returns (bool) {
        bool result = true;
        if(enablecappedWithdrawalLimit && !_isExcludedFromCap[from])
        {
                // reset locked to 0 after time expires
                if(block.timestamp.sub(_cappedWithdrawalArray[from].time) >= cappedWithdrawalTimeSpan)
                {
                        _cappedWithdrawalArray[from].amount = 0;
                }
                // increment the withrawal amount
                if(cappedWithdrawalLimit >= (_cappedWithdrawalArray[from].amount + amount))
                {              
                        _cappedWithdrawalArray[from].amount += amount;
                        _cappedWithdrawalArray[from].time = block.timestamp;
                }
                else{
                    result = false;
                    
                }                
        }

        return result;
    }

    function userWithdrawAmount(address from) public view returns (uint256) {
        return _cappedWithdrawalArray[from].amount;
    }

    function userWithdrawTime(address from) public view returns (uint256) {
        return _cappedWithdrawalArray[from].time;
    }

    function _partialFee(address from,uint256 amount) internal returns (uint256) {
        return amount.sub(_calculateFeeAmount(from,amount));
    }

    function _calculateFeeAmount(address from,uint256 amount) internal returns (uint256) {
        uint256 totalFeeAmount = 0;
        uint256 totalFees = communityFee.add(devFee).add(liquidityFee);

        uint256 contractTokenBalance = balanceOf(address(this));
        // Check the balance of the smart contract before making the swap
        if(contractTokenBalance >= swapTokensAtAmount && !automatedMarketMakerPairs[from] && enableSwap)
        {
             swapping = true;

             uint256 devFeeAmount = (contractTokenBalance.mul(devFee)).div(totalFees);
             swapTokensForEth(devFeeAmount,developer);

             uint256 communityFeeAmount = (contractTokenBalance.mul(communityFee)).div(totalFees);
             super._transfer(address(this),community,communityFeeAmount);

             uint256 liquidityFeeAmount = (contractTokenBalance.mul(liquidityFee)).div(totalFees);
             super._transfer(address(this),liquidity,liquidityFeeAmount);

             swapping = false;
        }

        totalFeeAmount  = (amount.mul(totalFees)).div(100);
        // send Tax Funds to the smart contract
        if(from != address(this))
        {
                super._transfer(from,address(this),totalFeeAmount);
        }
        return totalFeeAmount;
    }


     function swapTokensForEth(uint256 tokenAmount, address receiver) internal  {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            receiver,
            block.timestamp + (60 * 1000)
        );
    }

     // calculate price based on pair reserves
   function getTokenPrice(uint256 amount) public view returns(uint256)
   {
        (uint256 res0, uint256 res1,) = pair.getReserves();
        return((amount*res1)/res0); // return amount of eth needed to buy Gull
   }

    function withdrawTokenFunds(address token,address wallet) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(wallet != address(0), "Wallet should not be 0");

        IERC20 ercToken = IERC20(token);
        ercToken.transfer(wallet,ercToken.balanceOf(address(this)));
    }

}
