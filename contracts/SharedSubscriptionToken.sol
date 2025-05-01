// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./VotingSystem.sol";

/**
 * @title SharedSubscriptionToken
 * @dev Main contract that combines all functionality for the subscription system
 */
contract SharedSubscriptionToken is VotingSystem {
    string public name = "Shared Subscription Token";
    string public symbol = "SST";
    uint8 public decimals = 18;

    // Additional events
    event ConfigurationUpdated(string parameter, uint256 value);
    event EmergencyPause(bool paused);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    event TokensCashedOut(address indexed user, uint256 amount, uint256 ethReturned);
    
    // Emergency pause capability
    bool public paused;
    
    constructor() {
        // Initialize the contract
        paused = false;
    }
    
    // Emergency pause modifier
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
    
    // Instead of using super, we reimplement the full logic with the additional pause check
    function buyTokens(uint256 amount) external payable override nonReentrant whenNotPaused {
        require(msg.value >= amount * tokenPrice, "Insufficient payment");
        balanceOf[msg.sender] += amount;
        emit TokensPurchased(msg.sender, amount);
    }
    
    // Reimplement subscribe with pause check
    function subscribe(uint256 serviceId) external override whenNotPaused {
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
    
    // Emergency pause function
    function togglePause() external onlyOwner {
        paused = !paused;
        emit EmergencyPause(paused);
    }
    
    // Update token price
    function updateTokenPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be positive");
        tokenPrice = newPrice;
        emit ConfigurationUpdated("tokenPrice", newPrice);
    }
    
    // Update subscription duration
    function updateSubscriptionDuration(uint256 newDuration) external onlyOwner {
        require(newDuration > 0, "Duration must be positive");
        subscriptionDuration = newDuration;
        emit ConfigurationUpdated("subscriptionDuration", newDuration);
    }
    
    // Batch update of service costs
    function batchUpdateServiceCosts(
        uint256[] calldata serviceIds, 
        uint256[] calldata newCosts
    ) external onlyOwner {
        require(serviceIds.length == newCosts.length, "Arrays must be same length");
        
        for (uint256 i = 0; i < serviceIds.length; i++) {
            require(services[serviceIds[i]].exists, "Service does not exist");
            services[serviceIds[i]].cost = newCosts[i];
            emit ServiceCostUpdated(serviceIds[i], newCosts[i]);
        }
    }
    
    // Batch addition of services
    function batchAddServices(
        uint256[] calldata serviceIds, 
        string[] calldata symbols
    ) external onlyOwner {
        require(serviceIds.length == symbols.length, "Arrays must be same length");
        
        for (uint256 i = 0; i < serviceIds.length; i++) {
            require(!services[serviceIds[i]].exists, "Service already exists");
            
            services[serviceIds[i]].exists = true;
            services[serviceIds[i]].cost = 10 ether; // Default cost
            services[serviceIds[i]].symbol = symbols[i];
            services[serviceIds[i]].subscriptionCount = 0;
            
            emit ServiceAdded(serviceIds[i], symbols[i]);
        }
    }
    
    // Contract statistics
    function getContractStatistics() external view returns (
        uint256 totalServices,
        uint256 totalActiveSubscriptions,
        uint256 contractBalance
    ) {
        // Count total services
        uint256 serviceCount = 0;
        uint256 subscriptionCount = 0;
        
        // Note: This is a naive implementation that could be gas-intensive
        // In a production environment, you'd maintain counters
        for (uint256 i = 1; i <= 100; i++) { // Assuming service IDs start at 1
            if (services[i].exists) {
                serviceCount++;
                subscriptionCount += services[i].subscriptionCount;
            }
        }
        
        return (
            serviceCount,
            subscriptionCount,
            address(this).balance
        );
    }
    
    // Check if a user has active subscriptions across all services
    function getUserActiveSubscriptions(address user) external view returns (
        uint256[] memory serviceIds,
        bool[] memory isActive
    ) {
        // First count how many services exist to create properly sized arrays
        uint256 serviceCount = 0;
        for (uint256 i = 1; i <= 100; i++) {
            if (services[i].exists) {
                serviceCount++;
            }
        }
        
        serviceIds = new uint256[](serviceCount);
        isActive = new bool[](serviceCount);
        
        uint256 index = 0;
        for (uint256 i = 1; i <= 100; i++) {
            if (services[i].exists) {
                serviceIds[index] = i;
                
                // Check if user has an active subscription
                if (userSubscriptions[user][i].exists) {
                    uint256 accountId = userSubscriptions[user][i].accountId;
                    SubscriptionAccount storage account = subscriptionAccounts[i][accountId];
                    isActive[index] = account.active && account.expirationTime >= block.timestamp;
                } else {
                    isActive[index] = false;
                }
                
                index++;
            }
        }
        
        return (serviceIds, isActive);
    }
    
    // Transfer tokens between users (basic ERC20-like functionality)
    function transferTokens(address to, uint256 amount) external whenNotPaused {
        require(to != address(0), "Cannot transfer to zero address");
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        
        emit TokensTransferred(msg.sender, to, amount);
    }
    
    // Allow users to cash out unused tokens at a discount
    function cashOutTokens(uint256 amount) external nonReentrant whenNotPaused {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        // Set cashout rate at 70% of purchase price
        uint256 refundAmount = (tokenPrice * amount * 70) / 100;
        require(address(this).balance >= refundAmount, "Contract has insufficient balance");
        
        // Update state before external call
        balanceOf[msg.sender] -= amount;
        
        // Transfer ETH back to user
        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "ETH transfer failed");
        
        emit TokensCashedOut(msg.sender, amount, refundAmount);
    }
    
    // Function to get all members of a service (across all accounts)
    // Note: This could be gas intensive for services with many accounts
    function getAllServiceMembers(uint256 serviceId) external view returns (address[] memory) {
        require(services[serviceId].exists, "Service does not exist");
        
        uint256 totalMembers = 0;
        
        // First, count total members
        for (uint256 accountId = 1; accountId <= services[serviceId].subscriptionCount; accountId++) {
            SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
            if (account.active) {
                totalMembers += account.members.length;
            }
        }
        
        // Create the result array
        address[] memory allMembers = new address[](totalMembers);
        uint256 currentIndex = 0;
        
        // Populate the result array
        for (uint256 accountId = 1; accountId <= services[serviceId].subscriptionCount; accountId++) {
            SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
            if (account.active) {
                for (uint256 i = 0; i < account.members.length; i++) {
                    allMembers[currentIndex] = account.members[i];
                    currentIndex++;
                }
            }
        }
        
        return allMembers;
    }
    
    // Get expiration time for a user's subscription
    function getSubscriptionExpirationTime(address user, uint256 serviceId) external view returns (uint256) {
        require(userSubscriptions[user][serviceId].exists, "No subscription found");
        
        uint256 accountId = userSubscriptions[user][serviceId].accountId;
        return subscriptionAccounts[serviceId][accountId].expirationTime;
    }
    
    // Add other functions that need pause protection
    function renewSubscription(uint256 serviceId) external override whenNotPaused {
        // Call the parent implementation since this doesn't use 'super'
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        balanceOf[msg.sender] -= 1;
        account.expirationTime = block.timestamp + subscriptionDuration;
        account.active = true;
    }
    
    // Add pause protection to voting functions
    function proposeToKickUser(
        uint256 serviceId,
        uint256 accountId,
        address userToKick
    ) external override whenNotPaused {
        // Call parent implementation code directly instead of using super
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        require(account.isMember[msg.sender], "Not a member");
        require(account.isMember[userToKick], "User not in this account");
        require(userToKick != msg.sender, "Cannot propose yourself");

        require(
            block.timestamp > lastProposalTime[msg.sender] + 12 hours,
            "Wait before proposing again"
        );

        lastProposalTime[msg.sender] = block.timestamp;
        
        uint256 proposalId = ++proposalCounts[serviceId][accountId];
        Proposal storage proposal = proposals[serviceId][accountId][proposalId];
        
        proposal.proposer = msg.sender;
        proposal.userToKick = userToKick;
        proposal.endTime = block.timestamp + 1 days;
        
        emit ProposalCreated(serviceId, accountId, proposalId, msg.sender, userToKick);
    }
    
    function voteOnProposal(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId,
        bool vote
    ) external override whenNotPaused {
        // Implement full logic with pause check
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        Proposal storage proposal = proposals[serviceId][accountId][proposalId];
        
        if (!account.isMember[msg.sender]) revert NotMember();
        if (block.timestamp > proposal.endTime) revert VotingPeriodEnded();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();
        if (msg.sender == proposal.userToKick) revert NotMember();

        proposal.hasVoted[msg.sender] = true;
        if (vote) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }
        
        emit VoteCast(serviceId, accountId, proposalId, msg.sender, vote);
    }
    
    // Add pause protection to other key functions as needed
    function registerPublicKey(string calldata publicKey) external override whenNotPaused {
        require(bytes(publicKey).length > 0, "Public key cannot be empty");
        userPublicKeys[msg.sender] = publicKey;
        emit PublicKeyRegistered(msg.sender, publicKey);
    }
}