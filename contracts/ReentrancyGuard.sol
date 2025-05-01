// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ReentrancyGuard
 * @dev Contract module that helps prevent reentrant calls
 */
contract ReentrancyGuard {
    bool private _locked;
    
    constructor() {
        _locked = false;
    }
    
    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }
}