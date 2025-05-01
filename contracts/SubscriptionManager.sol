// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenBase.sol";
import "./ServiceManager.sol";

/**
 * @title SubscriptionManager
 * @dev Manages subscription accounts and memberships
 */
contract SubscriptionManager is TokenBase, ServiceManager {
    uint256 public subscriptionDuration = 30 days;
    uint256 public maxUsersPerSubscription = 5;
    
    struct SubscriptionAccount {
        bool active;
        uint256 expirationTime;
        address[] members;
        mapping(address => bool) isMember;
    }
    
    struct UserSubscription {
        bool exists;
        uint256 serviceId;
        uint256 accountId;
    }
    
    mapping(uint256 => mapping(uint256 => SubscriptionAccount)) public subscriptionAccounts;
    mapping(address => mapping(uint256 => UserSubscription)) public userSubscriptions;
    mapping(uint256 => uint256[]) public activeSubscriptionsByService;
    
    event SubscriptionAccountCreated(uint256 serviceId, uint256 accountId);
    event UserAddedToSubscription(address user, uint256 serviceId, uint256 accountId);
    event SubscriptionUpdate(uint256 serviceId, uint256 accountId, uint256 numMembers, uint256 costPerMember);
    
    modifier checkSubscriptionActive(uint256 serviceId) {
        if (userSubscriptions[msg.sender][serviceId].exists) {
            uint256 accountId = userSubscriptions[msg.sender][serviceId].accountId;
            SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
            
            if (account.active && account.expirationTime < block.timestamp) {
                account.active = false;
            }
            
            require(account.active, "Subscription has expired");
        } else {
            revert("Not subscribed to this service");
        }
        _;
    }
    
    function _getAvailableSubscriptionAccount(uint256 serviceId) internal view returns (uint256) {
        uint256[] memory activeAccounts = activeSubscriptionsByService[serviceId];
        uint256[] memory availableAccounts = new uint256[](activeAccounts.length);
        uint256 availableCount = 0;
        
        for (uint i = 0; i < activeAccounts.length; i++) {
            uint256 accountId = activeAccounts[i];
            if (subscriptionAccounts[serviceId][accountId].members.length < maxUsersPerSubscription) {
                availableAccounts[availableCount] = accountId;
                availableCount++;
            }
        }
        
        if (availableCount == 0) {
            return 0;
        }
        
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            msg.sender, 
            blockhash(block.number - 1),
            block.prevrandao
        ))) % availableCount;
        return availableAccounts[randomIndex];
    }
    
    function _createSubscriptionAccount(uint256 serviceId) internal returns (uint256) {
        uint256 accountId = services[serviceId].subscriptionCount + 1;
        incrementSubscriptionCount(serviceId);
        
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        account.active = true;
        account.expirationTime = block.timestamp + subscriptionDuration;
        
        activeSubscriptionsByService[serviceId].push(accountId);
        
        emit SubscriptionAccountCreated(serviceId, accountId);
        return accountId;
    }
    
    function subscribe(uint256 serviceId) external virtual {
        require(services[serviceId].exists, "Service does not exist");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        require(!userSubscriptions[msg.sender][serviceId].exists, "Already subscribed to this service");
        
        balanceOf[msg.sender] -= 1;
        
        uint256 accountId = _getAvailableSubscriptionAccount(serviceId);
        
        if (accountId == 0) {
            accountId = _createSubscriptionAccount(serviceId);
        }
        
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        account.members.push(msg.sender);
        account.isMember[msg.sender] = true;
        
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        userSub.exists = true;
        userSub.serviceId = serviceId;
        userSub.accountId = accountId;
        
        emit UserAddedToSubscription(msg.sender, serviceId, accountId);
    }
    
    function renewSubscription(uint256 serviceId) external virtual{
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        balanceOf[msg.sender] -= 1;
        account.expirationTime = block.timestamp + subscriptionDuration;
        account.active = true;
    }
    
    function calculateCostPerMember(uint256 serviceId, uint256 accountId) external {
        require(services[serviceId].exists, "Service does not exist");
        require(subscriptionAccounts[serviceId][accountId].active, "Subscription account not active");
        
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        uint256 memberCount = account.members.length;
        
        require(memberCount > 0, "No members in subscription");
        uint256 costPerMember = services[serviceId].cost / memberCount;
        
        emit SubscriptionUpdate(serviceId, accountId, memberCount, costPerMember);
    }
    
    function getSubscriptionMembers(uint256 serviceId, uint256 accountId) external view returns (address[] memory) {
        return subscriptionAccounts[serviceId][accountId].members;
    }
    
    function isSubscriptionActive(address user, uint256 serviceId) external view returns (bool) {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        if (!userSub.exists) return false;
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        return account.active && account.expirationTime >= block.timestamp;
    }
    
    function getUserSubscriptionDetails(address user, uint256 serviceId) external view 
        returns (bool exists, uint256 accountId) {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        return (userSub.exists, userSub.accountId);
    }
    
    function updateMaxUsersPerSubscription(uint256 newMax) external onlyOwner {
        maxUsersPerSubscription = newMax;
    }
}