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

    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Pair public pair;
    address public  uniswapV2Pair;
    address private developer = address(0xbDA5747bFD65F08deb54cb465eB87D40e51B197E);
    address private marketing = address(0xbDA5747bFD65F08deb54cb465eB87D40e51B197E);
    address private liquidity = address(0xbDA5747bFD65F08deb54cb465eB87D40e51B197E);
    address private community = address(0xbDA5747bFD65F08deb54cb465eB87D40e51B197E);

    bool private enableSwap   = false;
    bool private enableTaxFee = true;
    bool private enablecappedWithdrawalLimit = false;
    
    uint256 public cappedSupply = 150000000 * (10**18);
    // transfer fees
    uint256 public marketFee = 3;
    uint256 public devFee = 3;
    uint256 public communityFee = 3;
    uint256 public liquidityFee = 3;

    uint256 public cappedWithdrawalLimit = 50; // 50$ per determined time
    uint256 public cappedWithdrawalTimeSpan = 86400; // 50$ per day
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    constructor() ERC20("Gull", "GULL") {


       IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
      //  Create a uniswap pair for this new token
       address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this),_uniswapV2Router.WETH());

         // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        pair = IUniswapV2Pair(uniswapV2Pair);
     
        excludeFromFees(address(this), true);
        excludeFromFees(owner(), true);
        excludeFromFees(uniswapV2Pair, true);
        excludeFromCap(address(this), true);
        excludeFromCap(owner(), true);
        excludeFromCap(uniswapV2Pair, true);

        _mint(owner(), cappedSupply);
    }


    function mint(address to, uint amount) external onlyOwner{
        require(cappedSupply >= amount+totalSupply(), "Exceeded the capped amount");
        _mint(to, amount);
    }

    function burn(address owner, uint amount) external onlyOwner{
        _burn(owner, amount);
    }

    function addAdminRole(address admin) public onlyOwner{
        _setupRole(ADMIN_ROLE, admin);
    }

    function revokeAdminRole(address admin) public onlyOwner{
        revokeRole(ADMIN_ROLE, admin);
    }

    function adminRole(address admin) public view returns(bool){
        return hasRole(ADMIN_ROLE,admin);
    }
    
    function updateCappedWithdrawal(uint256 _cappedWithdrawalLimit) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        cappedWithdrawalLimit = _cappedWithdrawalLimit;
    }  

    function updateCappedWithdrawalTime(uint256 _cappedWithdrawalTimeSpan) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        cappedWithdrawalTimeSpan = _cappedWithdrawalTimeSpan;
    }

    function excludeFromFees(address account, bool excluded) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(_isExcludedFromFees[account] != excluded, "Account is already 'excluded'");
        _isExcludedFromFees[account] = excluded;
    }      

    function excludeFromCap(address account, bool excluded) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(_isExcludedFromCap[account] != excluded, "Account is already 'excluded'");
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

    function _transferFeesWallets(address newOwnerDev,address newOwnerMarket,address newOwnerAdd,address newOwnerCom) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        liquidity = newOwnerAdd;
        developer = newOwnerDev;
        marketing = newOwnerMarket;
        community = newOwnerCom;
    }

    function updateCappedWithdrawalToogle(bool _enablecappedWithdrawalLimit) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(enablecappedWithdrawalLimit != _enablecappedWithdrawalLimit, "it's the same state");
        enablecappedWithdrawalLimit = _enablecappedWithdrawalLimit;
    }

    function updateSwapToogle(bool _enableSwap) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(enableSwap != _enableSwap, "it's the same state");
        enableSwap = _enableSwap;
    }

    function updateFeesToogle(bool _enableTaxFee) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(enableTaxFee != _enableTaxFee, "it's the same state");
        enableTaxFee = _enableTaxFee;
    }



    function updateFees(uint256 _liquidityFee, uint256 _marketFee, uint256 _devFee, uint256 _communityFee) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        liquidityFee = _liquidityFee;
        marketFee = _marketFee;
        devFee = _devFee;
        communityFee = _communityFee;
        
    }

    function updateUniswapV2Router(address newAddress) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(newAddress != address(uniswapV2Router), "Already has that address");
        uniswapV2Router = IUniswapV2Router02(newAddress);
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
    }

    function _transfer(address from,address to, uint256 amount) internal override {
       require(acceptWithdraw(from,amount), "You exceeded the limit");

       uint256 newAmount = amount;
       if(!_isExcludedFromFees[from] && enableTaxFee)
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
        uint256 totalFees = liquidityFee.add(marketFee).add(devFee).add(communityFee);

        totalFeeAmount  = (amount.mul(totalFees)).div(100);

        uint256 marketFeeAmount = (amount.mul(marketFee)).div(100);
        uint256 devFeeAmount = (amount.mul(devFee)).div(100);
        uint256 communityFeeAmount = (amount.mul(communityFee)).div(100);
        uint256 liquidityFeeAmount = (amount.mul(liquidityFee)).div(100);

        if(from != address(this))
        {
                super._transfer(from,address(this),totalFeeAmount);
        }

        if(acceptSwap(marketFeeAmount))
        {
            swapTokensForEth(marketFeeAmount,marketing);
        }
        else{
            super._transfer(address(this),marketing,marketFeeAmount);
        }

        if(acceptSwap(devFeeAmount))
        {
            swapTokensForEth(devFeeAmount,developer);
        }
        else{
            super._transfer(address(this),developer,devFeeAmount);
        }

        if(balanceOf(address(this)) >= liquidityFeeAmount.add(communityFeeAmount))
        {
             super._transfer(address(this),community,communityFeeAmount);
             super._transfer(address(this),liquidity,liquidityFeeAmount);
        }

        return totalFeeAmount;
    }



   function acceptSwap(uint256 amount) public view returns (bool) {
        bool result = false;
        if(enableSwap)
        {
            (, uint256 res1,) = pair.getReserves();
            
            ERC20 token1 = ERC20(pair.token1());
            res1 = res1*(10**token1.decimals());

            if(res1 >= getTokenPrice(amount))
            {
                result = true;
            }
        }
        return result;
    }  


  function swapTokensForEth(uint256 tokenAmount, address receiver) internal {
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
            block.timestamp + 60 * 1000
        );
    }

    function exchangeTokensForEth(uint256 tokenAmount, address receiver)  external onlyOwner {
            swapTokensForEth(tokenAmount,receiver);
    }

     // calculate price based on pair reserves
   function getTokenPrice(uint256 amount) public view returns(uint256)
   {
        (uint256 res0, uint256 res1,) = pair.getReserves();
        return((amount*res1)/res0); // return amount of token0 needed to buy token1
   }





}