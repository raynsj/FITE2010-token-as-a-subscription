// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

/**
 * @title TokenBase
 * @dev Basic token functionality for the subscription system
 */
contract TokenBase is Ownable, ReentrancyGuard {
    uint256 public tokenPrice = 0.01 ether;
    mapping(address => uint256) public balanceOf;
    
    event TokensPurchased(address indexed buyer, uint256 amount);
    
    constructor() {
        balanceOf[msg.sender] = 1000; // Initial tokens for testing
    }
    
    function buyTokens(uint256 amount) external payable nonReentrant virtual{
        require(msg.value >= amount * tokenPrice, "Insufficient payment");
        balanceOf[msg.sender] += amount;
        emit TokensPurchased(msg.sender, amount);
    }
    
    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 contractBalance = address(this).balance;
        (bool success, ) = owner.call{value: contractBalance}("");
        require(success, "Transfer failed");
    }
    
    // Fallback function to receive ETH
    receive() external payable {}
}