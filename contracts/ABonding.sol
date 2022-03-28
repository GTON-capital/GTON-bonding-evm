//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IBasicBonding } from "./interfaces/IBasicBonding.sol";
import { IBondStorage } from "./interfaces/IBondStorage.sol";
import { IWhitelist } from "./interfaces/IWhitelist.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { IStaking } from "@gton/staking/contracts/interfaces/IStaking.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract ABonding is IBasicBonding, Ownable, ERC721Holder, ReentrancyGuard {

    constructor(
        uint _bondLimit,
        uint _bondActivePeriod,
        uint _bondToClaimPeriod, 
        uint _discountNominator,
        IBondStorage _bondStorage,
        AggregatorV3Interface _tokenAggregator,
        AggregatorV3Interface _gtonAggregator,
        ERC20 _token,
        ERC20 _gton,
        IStaking _sgton,
        string memory bondType_
        ) {
        bondLimit = _bondLimit;
        bondActivePeriod = _bondActivePeriod;
        bondToClaimPeriod = _bondToClaimPeriod;
        discountNominator = _discountNominator;
        bondStorage = _bondStorage;
        tokenAggregator = _tokenAggregator;
        gtonAggregator = _gtonAggregator;
        token = _token;
        gton = _gton;
        sgton = _sgton;
        _bondType = bytes(bondType_);
    }

    /* ========== MODIFIERS  ========== */

    /**
     * Mofidier checks if bonding period is open and provides access to the function
     * It is used for mint function.
     */

    modifier mintEnabled() {
        require(isWhitelistActive || isBondingActive(), 
            "Bonding: Mint is not available in this period");
        _;
    }

    /* ========== CONSTANTS ========== */

    uint constant public discountDenominator = 10000;

    /* ========== STATE VARIABLES ========== */

    bytes _bondType;
    uint public lastBondActivation;
    // amount in ms. Shows amount of time when this contract can issue the bonds
    uint public bondActivePeriod;
    // Amount in ms. Bond will be available to claim after this period of time
    uint public bondToClaimPeriod;
    uint public bondLimit;
    uint public bondCounter;
    uint public discountNominator;
    bool public isWhitelistActive;
    mapping (uint => BondData) public activeBonds;
    mapping(address => uint[]) public userBonds;
    IWhitelist public whitelist;

    struct BondData {
        bool isActive;
        uint issueTimestamp;
        uint releaseTimestamp;
        uint releaseAmount;
    }

    ERC20 immutable public token;
    ERC20 immutable  public gton;
    IStaking immutable public sgton;
    IBondStorage immutable public bondStorage;
    AggregatorV3Interface public tokenAggregator;
    AggregatorV3Interface public gtonAggregator;

    /* ========== VIEWS ========== */

    function isActiveBond(uint id) public view returns(bool) {
        return activeBonds[id].isActive;
    }

    function bondType() public view returns(string memory) {
        return string(_bondType);
    }

    /**
     * Function calculates amount of token to be earned with the `amount` by the bond duration time
     */
    function getStakingReward(uint amount) public view returns(uint) {
        uint stakingN = sgton.aprBasisPoints();
        uint stakingD = sgton.aprDenominator(); 
        uint calcDecimals = sgton.calcDecimals();
        uint secondsInYear = sgton.secondsInYear();
        //uint yearEarn = amount * calcDecimals * stakingN / stakingD;
        //return yearEarn * bondToClaimPeriod / secondsInYear / calcDecimals;
        return (amount * calcDecimals * stakingN * bondToClaimPeriod) / stakingD / secondsInYear / calcDecimals;
    }

    /**
     * View function returns timestamp when bond period vill be over
     */
    function bondingWindowEndTimestamp() public view returns(uint) {
        return lastBondActivation + bondActivePeriod;
    }

    /**
     * Function that returns data from aggregator
     */
    function tokenPriceAndDecimals(AggregatorV3Interface _token) internal view returns (int256 price, uint decimals) {
        decimals = _token.decimals();
        (, price,,,) = _token.latestRoundData();
    }

    /**
     * Function calculates the amount of gton out for current price without discount
     */
    function bondAmountOut(uint amountIn) public view returns (uint amountOut) {
        (int256 gtonPrice, uint gtonDecimals) = tokenPriceAndDecimals(gtonAggregator);
        (int256 tokenPrice, uint tokenDecimals) = tokenPriceAndDecimals(tokenAggregator);
        amountOut = amountIn * uint(tokenPrice) * gtonDecimals / tokenDecimals / uint(gtonPrice);
    }

    /**
     * Function calculates the  amount of token that represents
     */
    function amountWithoutDiscount(uint amount) public view returns (uint) {
        // to keep contract representation correctly
        uint givenPercent = discountDenominator - discountNominator;
        /**
            For example:
            discount - 25%
            givenPercent = 100-25 = 75
            amountWithoutDiscount = amount / 75 * 100
         */
        return amount * discountDenominator / givenPercent;
    }

    /**
     * Function checks if bond period is open by checking 
     * that last block timestamp is between bondEpiration timestamp and lastBondActivation timestamp.
     */
    function isBondingActive() public view returns(bool) {
        return block.timestamp >= lastBondActivation && block.timestamp <= bondingWindowEndTimestamp();
    }

    /**
     * Function returns total amount of bonds issued by this contract
     */
    function totalSupply() external view override returns(uint) {
        return bondCounter;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _mint(uint amount, address user, uint releaseTimestamp) internal nonReentrant returns(uint id) {
        require(bondLimit > bondCounter, "Bonding: Exceeded amount of bonds");
        uint amountWithoutDis = amountWithoutDiscount(amount);
        uint sgtonAmount = bondAmountOut(amountWithoutDis);
        bondCounter++;
        if(isWhitelistActive) {
            uint allowedAllocation = whitelist.allowedAllocation(user);
            require(sgtonAmount <= allowedAllocation, "Bonding: You are not allowed for this allocation");
            whitelist.updateAllocation(user, allowedAllocation - sgtonAmount);
        }
        uint reward = getStakingReward(sgtonAmount);
        uint bondReward = sgtonAmount + reward;

        id = bondStorage.mint(user, releaseTimestamp, bondReward);
        activeBonds[id] = BondData(true, block.timestamp, releaseTimestamp, bondReward);
        userBonds[user].push(id);
        //bondCounter++;

        emit Mint(id, user);
        emit MintData(address(token), bondReward, releaseTimestamp, bondType());
    }

    /**
     * Function receives the bond from user and updates users balance with sgton
     */
    function claim(uint tokenId) external override {
        // No need to add checks if bond was issued on this contract because the id of bond is unique
        require(isActiveBond(tokenId), "Bonding: Cannot claim inactive bond");
        BondData storage bond = activeBonds[tokenId];
        bond.isActive = false;
        bondStorage.safeTransferFrom(msg.sender, address(this), tokenId);
        //BondData storage bond = activeBonds[tokenId];
        require(bond.releaseTimestamp <= block.timestamp, "Bonding: Bond is locked to claim now");
        //bond.isActive = false;
        //gton.approve(address(sgton), bond.releaseAmount);
        if (!(gton.approve(address(sgton), bond.releaseAmount))) { revert(); }
        sgton.stake(bond.releaseAmount, msg.sender);
        emit Claim(msg.sender, tokenId);
    }

     /* ========== RESTRICTED ========== */
    
    /**
     * Function starts issue bonding period
     */
    function startBonding() external override onlyOwner {
        require(!isBondingActive(), "Bonding: Bonding is already active");
        lastBondActivation = block.timestamp;
    }

    function setGtonAggregator(AggregatorV3Interface agg) external onlyOwner {
        gtonAggregator = agg;
    }

    function setTokenAggregator(AggregatorV3Interface agg) external onlyOwner {
        tokenAggregator = agg;
    }

    function setDiscountNominator(uint _discountN) external onlyOwner {
        discountNominator = _discountN;
    }

    function setBondActivePeriod(uint _bondActivePeriod) external onlyOwner {
        bondActivePeriod = _bondActivePeriod;
    }

    function setBondToClaimPeriod(uint _bondToClaimPeriod) external onlyOwner {
        bondToClaimPeriod = _bondToClaimPeriod;
    }

    function setBondLimit(uint _bondLimit) external onlyOwner {
        bondLimit = _bondLimit;
    }

    function setWhitelist(IWhitelist _whitelist) external onlyOwner {
        whitelist = _whitelist;
    }

    function toggleWhitelist() external onlyOwner {
        isWhitelistActive = !isWhitelistActive;
    }
    
    function transferToken(ERC20 _token, address user) external onlyOwner {
        require(_token.transfer(user, _token.balanceOf(address(this))));
    }
}
