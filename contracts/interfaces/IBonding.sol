//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IBasicBonding } from "./IBasicBonding.sol";

interface IBonding is IBasicBonding {
    /**
     * @dev Mints new token for message sender.
     * Params:
     * - amount - the amount user wants to spend
     *
     * Emits {Mint} and {MintData} events
     */
    function mint(uint amount) external returns (uint tokenId);
}
