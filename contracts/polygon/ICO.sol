// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "./__unstable__TokenVault.sol";
import "./crowdsale/Crowdsale.sol";
import "./crowdsale/validation/CappedCrowdsale.sol";
import "./crowdsale/validation/PausableCrowdsale.sol";
import "./crowdsale/validation/TimedCrowdsale.sol";
import "./crowdsale/validation/WhitelistCrowdsale.sol";

import "./access/roles/WhitelistedRole.sol";
import "./access/roles/WhitelistAdminRole.sol";
import "./access/roles/CapperRole.sol";
import "./ownership/Ownable.sol";
import "./utils/ReentrancyGuard.sol";
import "./TokenVesting.sol";

import "./token/ERC20/IERC20.sol";

contract TSTokenPrivateSale is
    Crowdsale,
    CappedCrowdsale,
    CapperRole,
    PausableCrowdsale,
    WhitelistCrowdsale,
    TimedCrowdsale,
    Ownable
{
    using SafeMath for uint;
    
    struct User 
    {
        address inviter;
        address self;
    } 
    
    mapping(address => uint256) private _contributions;
    mapping(address => uint256) private _caps;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _commisions;
    mapping(address => TokenVesting) private _vault;
    mapping(address => __unstable__TokenVault) private _firstVault;
    mapping(address => User) public tree;
    mapping(address => bool) private _firstWithdraw;
    
    event SetNewCapValue(address indexed userAddress, uint256 newAmount);
    event WhitelistedListAdded(address[] indexed account);

    AffynToken _token; 
        
    uint256 private _individualDefaultCap;
    
    uint256 _openingTime;
    uint256 _closingTime;
    uint256 _totalCap; 
    address payable _wallet;
    uint256 _rate;
    
    uint256 private _cliffDuration;
    uint256 private _vestDuration;
    uint256 private _lockedAfterFirstWithdraw;
    

    constructor(
        AffynToken tokenAddress, uint256 totalSaleCap, uint256 individualPurchaseCap, uint256 openingTime, uint256 closingTime,
        address payable walletAddress, uint256 rate, uint256 cliffDuration, uint256 vestDuration, uint256 startCliffAfterFirstWithdrawTime)

        public
        WhitelistCrowdsale()
        PausableCrowdsale()
        CappedCrowdsale(totalSaleCap)
        TimedCrowdsale(openingTime, closingTime)
        Crowdsale(rate, walletAddress, tokenAddress)
    {
        tree[msg.sender] = User(msg.sender, msg.sender);
        _token = AffynToken(tokenAddress);
        _totalCap = totalSaleCap;
        _individualDefaultCap = individualPurchaseCap;
        _openingTime = openingTime;
        _closingTime = closingTime;
        _wallet = walletAddress;
        _rate = rate;
        _cliffDuration = cliffDuration;
        _vestDuration = vestDuration;
        _lockedAfterFirstWithdraw = startCliffAfterFirstWithdrawTime;
    }
    
     /**
     * @dev Change beneficiary Cliff time.
     * @param newTime new time for the cliff
     * @param beneficiary that is affected
     */
    function changeCliffWalletWithdrawTime(uint256 newTime, address beneficiary) public onlyOwner {
        _vault[beneficiary].extendCliffDuration(newTime);
    }
    
    /**
     * @dev Change beneficiary total vest time.
     * @param newTime new time for the cliff
     * @param beneficiary that is affected
     */
    function changeCliffWalletEndTime(uint256 newTime, address beneficiary) public onlyOwner {
        _vault[beneficiary].extendVestDuration(newTime);
    }

         /**
     * @dev Change beneficiary Cliff time.
     * @param newTime new time for the cliff
     * @param beneficiaries that is affected
     */
    function changeCliffWalletWithdrawTimeList(uint256 newTime, address[] calldata beneficiaries) external onlyOwner {
        for (uint256 index = 0; index < beneficiaries.length; index++) 
        {
            _vault[beneficiaries[index]].extendCliffDuration(newTime);
        }
    }
    
    /**
     * @dev Change beneficiary total vest time.
     * @param newTime new time for the cliff
     * @param beneficiaries that is affected
     */
    function changeCliffWalletEndTimeList(uint256 newTime, address[] calldata beneficiaries) external onlyOwner {
        for (uint256 index = 0; index < beneficiaries.length; index++) 
        {
            _vault[beneficiaries[index]].extendVestDuration(newTime);
        }
    }
    
     /**
     * @dev Sets a specific beneficiary's maximum contribution.
     * @param beneficiary Address to be capped
     * @param cap Wei limit for individual contribution
     */
    function setCap(address beneficiary, uint256 cap) external onlyCapper {
        _caps[beneficiary] = cap;
        emit SetNewCapValue(address(beneficiary), cap);
    }

    /**
     * @dev Returns the cap of a specific beneficiary.
     * @param beneficiary Address whose cap is to be checked
     * @return Current cap for individual beneficiary
     */
    function getCap(address beneficiary) public view returns (uint256) {
        uint256 cap = _caps[beneficiary];
        if (cap == 0) {
            cap = _individualDefaultCap;
        }
        return cap;
    }

    /**
     * @dev Returns the amount contributed so far by a specific beneficiary.
     * @param beneficiary Address of contributor
     * @return Beneficiary contribution so far
     */
    function getContribution(address beneficiary) public view returns (uint256) {
        return _contributions[beneficiary];
    }

    /**
     * @dev Extend parent behavior requiring purchase to respect the beneficiary's funding cap.
     * @param beneficiary Token purchaser
     * @param weiAmount Amount of wei contributed
     */
    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        require(isWhitelisted(beneficiary), "WhitelistCrowdsale: beneficiary doesn't have the Whitelisted role");
        super._preValidatePurchase(beneficiary, weiAmount);
        // solhint-disable-next-line max-line-length
        require(_contributions[beneficiary].add(weiAmount) <= getCap(beneficiary), "Contract: beneficiary's cap exceeded");
    }

    /**
     * @dev Extend parent behavior to update beneficiary contributions.
     * @param beneficiary Token purchaser
     * @param weiAmount Amount of wei contributed
     */
    function _updatePurchasingState(address beneficiary, uint256 weiAmount) internal {
        super._updatePurchasingState(beneficiary, weiAmount);
        _contributions[beneficiary] = _contributions[beneficiary].add(weiAmount);
    }
    
    /**
     * @dev Extends crowdsale end timing.
     * @param closingTime new closing time
    */
    function extendTime(uint256 closingTime) public onlyOwner {
        super._extendTime(closingTime);
    }
    
    /**
     * @dev Force close of crowdsale.
    */
    function closeCrowdSale() public onlyOwner {
        super._forceClosed();
    }
    
    /**
     * @dev get referral of said address.
    */
    function getInviter() public view returns (address) {
        return tree[msg.sender].inviter;
    }
    
    /**
     * @dev Extended version of adding Whitelisted
     * @param accounts the addresses you wish to whitelist
    */
    function addWhitelistedList(address[] calldata accounts) external onlyWhitelistAdmin
    {
        for (uint256 account = 0; account < accounts.length; account++) 
        {
            addWhitelisted(accounts[account]);
        }
        //emit WhitelistedListAdded(address[] accounts);
    }
    
    /**
     * @dev Reward 10 percent of purchased amount to the referree if there was
     * @param tokenAmount amount purchased
     * @param beneficiary purchaser wallet address
    */
    function _processCommision(uint256 tokenAmount, address beneficiary) internal {
        if (tree[beneficiary].inviter != address(0))
        {
            if (tree[beneficiary].inviter != beneficiary) //Do not reward commision to self
            {
                if (address(_vault[tree[beneficiary].inviter]) == address(0))
                {
                    _vault[tree[beneficiary].inviter] = new TokenVesting(tree[beneficiary].inviter, _closingTime + _lockedAfterFirstWithdraw, _cliffDuration, _vestDuration, false);
                }
                uint256 commisionReward = (tokenAmount / 10); //Get 10% of tokenAmount
                _balances[tree[beneficiary].inviter] = _balances[tree[beneficiary].inviter].add(commisionReward);
                _commisions[tree[beneficiary].inviter] = _commisions[tree[beneficiary].inviter].add(commisionReward);
                _deliverTokens(address(_vault[tree[beneficiary].inviter]), commisionReward);
            }   
        }
    }
    
    /**
     * @dev Withdraw tokens only after crowdsale ends.
     */
    function withdrawTokens() public {
        require(hasClosed(), "PostDeliveryCrowdsale: not closed");
        uint256 amount = _balances[msg.sender];
        require(amount > 0, "PostDeliveryCrowdsale: beneficiary is not due any tokens");

        if (_firstWithdraw[msg.sender] == false)
        {
            if (amount != _commisions[msg.sender]) //if beneficiary only earned from commisions and did not purchase token, ignore withdrawing from 10% wallet
            {
                uint256 firstWithdrawAmount = (amount - _commisions[msg.sender]) / 10;
                //Withdraw from 10% wallet
                _balances[msg.sender] -= firstWithdrawAmount;
                _firstVault[msg.sender].transfer(token(), msg.sender, firstWithdrawAmount);
                _firstWithdraw[msg.sender] = true;
            }
        }

        _balances[msg.sender] -= _vault[msg.sender]._releasableAmount(token());
        _vault[msg.sender].release(token());

    }
    
    /**
     * @dev check how much commisions was earned
     * @param beneficiary the address in question
    */
    function checkCommisions(address beneficiary) public view returns (uint256) {
        return _commisions[beneficiary];
    }
    
    /**
     * @dev check total balance in cliff vault
     * @param beneficiary the address in question
    */
    function checkTotalBalanceInCliff(address beneficiary) public view returns (uint256) {
        return _vault[beneficiary].getTotalAmount(token());
    }
    
    /**
     * @dev check how much can be withdrawn
     * @param beneficiary the address in question
    */
    function checkWithdrawAmount(address beneficiary) public view returns (uint256) {
        return _vault[beneficiary]._releasableAmount(token());
    }
    
    /**
     * @dev check how much left in cliff vault
     * @param beneficiary the address in question
    */
    function checkLeftAmount(address beneficiary) public view returns (uint256) {
        return _vault[beneficiary].getLeftoverAmount(token());
    }
    
    /**
     * @dev check cliff time of said address
     * @param beneficiary the address in question
    */
    function checkCliffTime(address beneficiary) public view returns (uint256) {
        return _vault[beneficiary].cliff();
    }
    
    /**
     * @dev check what time was vault starting time 
     * @param beneficiary the address in question
    */
    function checkStartTime(address beneficiary) public view returns (uint256) {
        return _vault[beneficiary].start();
    }

    /**
     * @return the balance of an account.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Overrides parent by storing due balances, and delivering tokens to the vault instead of the end user. This
     * ensures that the tokens will be available by the time they are withdrawn (which may not be the case if
     * `_deliverTokens` was called later).
     * @param beneficiary Token purchaser
     * @param tokenAmount Amount of tokens purchased
     */
    function _processPurchase(address beneficiary, uint256 tokenAmount) internal {
        if (address(_vault[beneficiary]) == address(0))
        {
            _vault[beneficiary] = new TokenVesting(beneficiary, _closingTime + _lockedAfterFirstWithdraw, _cliffDuration, _vestDuration, false);
        }
        if (address(_firstVault[beneficiary]) == address(0))
        {
            _firstVault[beneficiary] = new __unstable__TokenVault();
        }
        
        _firstWithdraw[beneficiary] = false;
        _balances[beneficiary] = _balances[beneficiary].add(tokenAmount);
        _deliverTokens(address(_vault[beneficiary]), tokenAmount - (tokenAmount / 10)); //Deliver 90% to cliff wallet
        _deliverTokens(address(_firstVault[beneficiary]), (tokenAmount / 10)); //Deliver 10% to first withdraw wallet
        _processCommision(tokenAmount, beneficiary);
    }
    
    /**
     * @dev extended function of purchase token, with amount purchased and reffral address, this should only be called once, moving forward should call buyTokens
     * @param beneficiary the address in question
     * @param referee refferal address
    */
    function buyTokensWithReferee(address beneficiary, address referee, uint256 amount) public {
        require(tree[beneficiary].inviter == address(0), "Sender can't already exist in tree");
        require(referee != beneficiary, "Referee cannot be yourself");
        
        tree[beneficiary] = User(referee, beneficiary);        
        buyTokens(beneficiary, amount);
    }

    // function usdtBuyTokensTest(address beneficiary, uint256 amount) public nonReentrant {
    //     uint256 weiAmount = amount;
    //     _preValidatePurchase(beneficiary, weiAmount);

    //     // calculate token amount to be created
    //     uint256 tokens = _getTokenAmount(weiAmount);

    //     // update state
    //     _weiRaised = _weiRaised.add(weiAmount);

    //     _processPurchase(beneficiary, tokens);
    //     emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);

    //     _updatePurchasingState(beneficiary, weiAmount);

    //     _forwardFundsUSDT(amount);
    //     _postValidatePurchase(beneficiary, weiAmount);
    // }

    // function _forwardFundsUSDT(uint256 amount) internal {
    //     // Transfer amount USDT tokens from msg.sender to contract
    //     usdt.transferFrom(_msgSender(), _wallet, amount);
    // }
}
