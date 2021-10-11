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
    address private developer = address(0xbDA5747bFD65F08deb54cb465eB87D40e51B197E);
    address private community = address(0xbDA5747bFD65F08deb54cb465eB87D40e51B197E);
    bool private swapping = false;

    bool private enableSwap   = true;
    bool private enableTaxFee = true;
    bool private enablecappedWithdrawalLimit = true;
    
    uint256 public constant CAPPED_SUPPLY = 150000000 * (10**18);
    // transfer fees
    uint256 public devFee = 6;
    uint256 public communityFee = 2;
    uint256 public liquidityFee = 2;
    uint256 public swapTokensAtAmount = 10000 * (10**18);

    uint256 public cappedWithdrawalLimit = 8000 * (10**18); // 100 $GULL per determined time
    uint256 public cappedWithdrawalTimeSpan = 1 days; // 100 $GULL per 100 sec
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event LimitReached(
        address account,
        uint256 time,
        bool value
    );

    constructor() ERC20("Gull", "GULL") {


       IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
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

        excludeFromCap(address(this), true);
        excludeFromCap(address(_uniswapV2Router), true);
        excludeFromCap(owner(), true);
        excludeFromCap(_uniswapV2Pair, true);
        excludeFromCap(developer, true);
        excludeFromCap(community, true);

        setAutomatedMarketMakerPair(_uniswapV2Pair, true);
        setAutomatedMarketMakerPair(address(uniswapV2Router), true);

        _mint(owner(), CAPPED_SUPPLY);
    }

    receive() external payable{

    }


    function mint(address to, uint amount) external onlyOwner{
        require(CAPPED_SUPPLY >= amount+totalSupply(), "Exceeded the capped amount");
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
    
    function updateCappedWithdrawal(uint256 _cappedWithdrawalLimit) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        require(_cappedWithdrawalLimit >= (5000 * (10**18)), "5k is the min amount");
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

    function _transferFeesWallets(address newOwnerDev,address newOwnerCom) public {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        developer = newOwnerDev;
        community = newOwnerCom;

        excludeFromCap(newOwnerDev, true);
        excludeFromCap(newOwnerCom, true);
        
        excludeFromFees(newOwnerDev, true);
        excludeFromFees(newOwnerCom, true);
    }

    function updateCappedWithdrawalToogle(bool _enablecappedWithdrawalLimit) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        enablecappedWithdrawalLimit = _enablecappedWithdrawalLimit;
    }

    function updateSwapTokenAmount(uint256 _swapTokensAtAmount) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        swapTokensAtAmount = _swapTokensAtAmount;
    }

    function updateSwapToogle(bool _enableSwap) external{
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        enableSwap = _enableSwap;
    }

    function updateFeesToogle(bool _enableTaxFee) external{
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

        emit LimitReached(from,_cappedWithdrawalArray[from].time,!result);
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
             swapAndLiquify(liquidityFeeAmount);

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


    function swapAndLiquify(uint256 tokens) private  {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.div(2);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half,address(this)); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
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

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp + (60 * 1000)
        );
    }

     // calculate price based on pair reserves
   function getTokenPrice(uint256 amount) public view returns(uint256)
   {
        (uint256 res0, uint256 res1,) = pair.getReserves();
        return((amount*res1)/res0); // return amount of eth needed to buy Gull
   }

    function withdrawTokenFunds(address token,address wallet) external onlyOwner {
        IERC20 ercToken = IERC20(token);
        ercToken.transfer(wallet,ercToken.balanceOf(address(this)));
    }

}
