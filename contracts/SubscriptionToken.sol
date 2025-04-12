// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// testing

/**
 * @title SubscriptionToken
 * @dev A contract that implements token-as-a-subscription functionality
 */
contract SubscriptionToken {
    address public owner;
    uint256 public tokenPrice = 0.01 ether;
    uint256 public subscriptionDuration = 30 days;
    
    struct Service {
        bool exists;
        uint256 cost;
    }
    
    struct Subscription {
        bool active;
        uint256 expirationTime;
    }
    
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => Service) public services;
    mapping(address => mapping(uint256 => Subscription)) public subscriptions;
    mapping(uint256 => uint256) public platformRequests;
    mapping(uint256 => address[]) public subscribersByPlatform;
    
    event SubscriptionUpdate(
        uint256 platformId, 
        uint256 numSubscribers, 
        uint256 costPerSubscriber
    );
    
    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = 1000; // Initial tokens for testing
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
    
    function buyTokens(uint256 amount) external payable {
        require(msg.value >= amount * tokenPrice, "Insufficient payment");
        balanceOf[msg.sender] += amount;
    }
    
    function activateSubscription(address user, uint256 serviceId) external {
        require(services[serviceId].exists, "Service does not exist");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        
        balanceOf[msg.sender] -= 1;
        subscriptions[user][serviceId].active = true;
        subscriptions[user][serviceId].expirationTime = block.timestamp + subscriptionDuration;
        
        // Add to subscribers list if not already there
        bool found = false;
        for (uint i = 0; i < subscribersByPlatform[serviceId].length; i++) {
            if (subscribersByPlatform[serviceId][i] == user) {
                found = true;
                break;
            }
        }
        if (!found) {
            subscribersByPlatform[serviceId].push(user);
        }
    }
    
    function checkAndExpireSubscriptions() external {
        for (uint256 serviceId = 1; serviceId <= 10; serviceId++) {
            if (services[serviceId].exists) {
                for (uint i = 0; i < subscribersByPlatform[serviceId].length; i++) {
                    address user = subscribersByPlatform[serviceId][i];
                    if (subscriptions[user][serviceId].active &&
                        subscriptions[user][serviceId].expirationTime < block.timestamp) {
                        subscriptions[user][serviceId].active = false;
                    }
                }
            }
        }
    }
    
    function requestNewPlatform(address user, uint256 platformId) external {
        platformRequests[platformId]++;
    }
    
    function checkSubscribers(uint256 platformId) external view returns (uint256) {
        uint256 count = 0;
        for (uint i = 0; i < subscribersByPlatform[platformId].length; i++) {
            address user = subscribersByPlatform[platformId][i];
            if (subscriptions[user][platformId].active) {
                count++;
            }
        }
        return count;
    }
    
    function divideCost(uint256 platformId) external {
        require(services[platformId].exists, "Service does not exist");
        
        uint256 activeSubscribers = 0;
        for (uint i = 0; i < subscribersByPlatform[platformId].length; i++) {
            address user = subscribersByPlatform[platformId][i];
            if (subscriptions[user][platformId].active) {
                activeSubscribers++;
            }
        }
        
        require(activeSubscribers > 0, "No active subscribers");
        uint256 costPerSubscriber = services[platformId].cost / activeSubscribers;
        
        emit SubscriptionUpdate(platformId, activeSubscribers, costPerSubscriber);
    }
    
    function addService(uint256 serviceId) external onlyOwner {
        services[serviceId].exists = true;
        services[serviceId].cost = 10 ether; // Default cost
    }
    
    function withdrawFunds() external onlyOwner {
    uint256 amount = address(this).balance;
    // Update state before external call
    uint256 contractBalance = amount;
    amount = 0;
    
    // Perform external call after state updates
    (bool success, ) = owner.call{value: contractBalance}("");
    require(success, "Transfer failed");
}
    
    function fallbackFunction(address user, uint256 platformId) external {
        if (balanceOf[user] >= 1 && services[platformId].exists) {
            balanceOf[user] -= 1;
            subscriptions[user][platformId].active = true;
            subscriptions[user][platformId].expirationTime = block.timestamp + subscriptionDuration;
        }
    }
    
    // Helper functions for testing
    function isSubscriptionActive(address user, uint256 serviceId) external view returns (bool) {
        return subscriptions[user][serviceId].active;
    }
    
    function getServiceCost(uint256 serviceId) external view returns (uint256) {
        return services[serviceId].cost;
    }
    
    // Fallback function to receive ETH
    receive() external payable {}
}
