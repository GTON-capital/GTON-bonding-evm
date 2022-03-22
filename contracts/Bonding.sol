//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { ABonding } from "./ABonding.sol";
import { IBondStorage } from "./interfaces/IBondStorage.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { Staking } from "@gton/staking/contracts/Staking.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";


contract Bonding is ABonding {

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
        Staking _sgton,
        string memory _bondType
        ) ABonding(
            _bondLimit, 
            _bondActivePeriod, 
            _bondToClaimPeriod, 
            _discountNominator,
            _bondStorage, 
            _tokenAggregator,
            _gtonAggregator,
            _token,
            _gton,
            _sgton,
            _bondType
        ){}

     /* ========== RESTRICTED ========== */

    /**
     * Function issues bond to user by minting the NFT token for them.
     */
    function mint(uint amount) public mintEnabled returns(uint id) {
        token.transferFrom(msg.sender, address(this), amount);
        uint releaseTimestamp = block.timestamp + bondToClaimPeriod;
        id = _mint(amount, msg.sender, releaseTimestamp);
    }
}
