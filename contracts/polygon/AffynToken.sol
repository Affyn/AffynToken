// contracts/AffynToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "./token/ERC20/ERC20.sol";
import "./token/ERC20/ERC20Detailed.sol";

/**
 * @title AffynToken
 * @dev Very simple ERC20 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `ERC20` functions.
 */
contract AffynToken is Context, ERC20, ERC20Detailed {

    /**
     * @dev Constructor that gives _msgSender() all of existing tokens.
     */
    string tokenName = "Affyn";
    string tokenTicker = "FYN";
    uint256 initSupply = 1000000000;

    constructor ()
        public ERC20Detailed(tokenName, tokenTicker, 18) {
        _mint(_msgSender(), initSupply * (10 ** uint256(decimals())));
    }
}
