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
    //mapping(address => __unstable__TokenVault) private _firstVault;
    mapping(address => User) public tree;
    //mapping(address => bool) private _firstWithdraw;

    event SetNewCapValue(address indexed userAddress, uint256 newAmount);
    event WhitelistedListAdded(address[] indexed account);
    event OwnershipChanged(address indexed prevOwner, address indexed newOwner);

    AffynToken _token;

    uint256 private _individualDefaultCap; //Cap for each user

    uint256 _openingTime;
    uint256 _closingTime;
    uint256 _totalCap;  // Total cap to be sold
    address payable _wallet; //Wallet to receive funds
    uint256 _rate;

    uint256 private _cliffDuration; //Duration of each cliff
    uint256 private _vestDuration; //Total duration of vest
    uint256 private _lockedAfterFirstWithdraw; //Locked for how many days after ICO ends before vesting period starts

    uint256 private totalTokensAvailable;


    // AffynToken tokenAddress = AffynToken(0xF1612621Fa28F2c65fc9c6AF73973FC19d44696D);
    // uint256 __totalSaleCap = 130000000000000000000000000;
    // uint256 __individualPurchaseCap = 50000000000000000000000;
    // uint256 __openingTime  = now + 30 minutes;
    // uint256 __closingTime  = __openingTime + 30 minutes;
    // address payable walletAddress = address(0x8B824a8e8096F67d3d48D5E7021aBdDC93d08CF6);
    // uint256 __rate = 125;
    // uint256 __cliffDuration = 1 minutes;
    // uint256 __vestDuration = 30 minutes;
    // uint256 __startCliffAfterFirstWithdrawTime = 10 minutes;
    // constructor()

    constructor(
        AffynToken tokenAddress, uint256 totalSaleCap, uint256 individualPurchaseCap, uint256 openingTime, uint256 closingTime,
        address payable walletAddress, uint256 rate, uint256 cliffDuration, uint256 vestDuration, uint256 startCliffAfterFirstWithdrawTime)

        public
        WhitelistCrowdsale()
        PausableCrowdsale()
        CappedCrowdsale(totalSaleCap)
        TimedCrowdsale(openingTime, closingTime)
        Crowdsale(rate, walletAddress, tokenAddress)
        // CappedCrowdsale(__totalSaleCap)
        // TimedCrowdsale(__openingTime, __closingTime)
        // Crowdsale(__rate, walletAddress, tokenAddress)
    {
        tree[_msgSender()] = User(_msgSender(), _msgSender());
        _token = AffynToken(tokenAddress);
        _wallet = walletAddress;
        totalTokensAvailable = 0;

        _openingTime = openingTime;
        _closingTime = closingTime;
        _totalCap = totalSaleCap;
        _individualDefaultCap = individualPurchaseCap;
        _rate = rate;
        _cliffDuration = cliffDuration;
        _vestDuration = vestDuration;
        _lockedAfterFirstWithdraw = startCliffAfterFirstWithdrawTime;

        // _openingTime = __openingTime;
        // _closingTime = __closingTime;
        // _totalCap = __totalSaleCap;
        // _individualDefaultCap = __individualPurchaseCap;
        // _rate = __rate;
        // _cliffDuration = __cliffDuration;
        // _vestDuration = __vestDuration;
        // _lockedAfterFirstWithdraw = __startCliffAfterFirstWithdrawTime;

    }

    function DepositRequiredAffyn() public onlyOwner {
        uint256 amount = _totalCap + (_totalCap / 10);
        _token.transferFrom(_msgSender(), address(this), amount); //Transfer total cap + commision tokens
        totalTokensAvailable = amount;
    }

    function getAffynLeftovers() public view returns (uint256) {
        return totalTokensAvailable;
    }

    function WithdrawRemainingAffyn() public onlyOwner {
        require(hasClosed(), "PostDeliveryCrowdsale: not closed");
        _deliverTokens(address(_wallet), totalTokensAvailable);
        totalTokensAvailable = 0;
    }

     /**
     * @dev Change ownership.
     * @param beneficiary new owner address
     */
    function TransferAllOwnership(address beneficiary) public onlyOwner {
    CapperRole.addCapper(beneficiary);
    super.addWhitelistAdmin(beneficiary);
    Ownable.transferOwnership(beneficiary);

    emit OwnershipChanged(address(_msgSender()), address(beneficiary));

    CapperRole.renounceCapper();
    super.renounceWhitelistAdmin();
    Ownable.renounceOwnership();
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
        require(isWhitelisted(beneficiary) || isPrebuyer(beneficiary), "WhitelistCrowdsale: beneficiary doesn't have the Whitelisted or Prebuyer role");
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
        return tree[_msgSender()].inviter;
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
    }

        /**
     * @dev Extended version of adding Prebuyer
     * @param accounts the addresses you wish to whitelist
    */
    function addPrebuyerList(address[] calldata accounts) external onlyWhitelistAdmin
    {
        for (uint256 account = 0; account < accounts.length; account++)
        {
            addPrebuyer(accounts[account]);
        }
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
                totalTokensAvailable = totalTokensAvailable - commisionReward;
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
        uint256 amount = _balances[_msgSender()];
        require(amount > 0, "PostDeliveryCrowdsale: beneficiary is not due any tokens");
        _balances[_msgSender()] -= _vault[_msgSender()]._releasableAmount(token());
        _vault[_msgSender()].release(token());

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

        _balances[beneficiary] = _balances[beneficiary].add(tokenAmount);
        _deliverTokens(address(_vault[beneficiary]), tokenAmount); //Deliver 100% to cliff wallet
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
        
        totalTokensAvailable = totalTokensAvailable - super._getTokenAmount(amount);
    }

    function buyTokensNoRef(address beneficiary, uint256 amount) public {
        buyTokens(beneficiary, amount);
        totalTokensAvailable = totalTokensAvailable - super._getTokenAmount(amount);
    }
}