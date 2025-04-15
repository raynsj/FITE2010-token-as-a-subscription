// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SharedSubscriptionToken
 * @dev A contract that implements token-as-a-subscription functionality with shared accounts
 */
contract SharedSubscriptionToken {
    address public owner;
    uint256 public tokenPrice = 0.01 ether;
    uint256 public subscriptionDuration = 30 days;
    uint256 public maxUsersPerSubscription = 5; // Maximum users per subscription account
    
    mapping(address => uint256) public lastProposalTime;

    struct ServiceInfo {
        bool exists;
        uint256 cost;
        string symbol; // Service symbol/identifier
        uint256 subscriptionCount; // Number of active subscription accounts for this service
    }
    
    struct SubscriptionAccount {
        bool active;
        uint256 expirationTime;
        address[] members; // Users who share this subscription
        string encryptedUsername; // Base username for the account (encrypted)
        string encryptedPassword; // Base password for the account (encrypted)
        mapping(address => bool) isMember; // Quick lookup for membership
        mapping(address => bytes) encryptedCredentials; // User-specific encrypted credentials
        //Jayden added
        mapping(uint256 => Proposal) proposals; // proposalId => Proposal
        uint256 proposalCount; // Total proposals for this account
    }
    
    struct UserSubscription {
        bool exists;
        uint256 serviceId;
        uint256 accountId; // Which subscription account they belong to
    }
    
    // Main mappings
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => ServiceInfo) public services;
    mapping(uint256 => mapping(uint256 => SubscriptionAccount)) public subscriptionAccounts; // serviceId => accountId => SubscriptionAccount
    mapping(address => mapping(uint256 => UserSubscription)) public userSubscriptions; // user => serviceId => UserSubscription
    mapping(uint256 => uint256[]) public activeSubscriptionsByService; // serviceId => array of active accountIds
    
    // Events
    event SubscriptionAccountCreated(uint256 serviceId, uint256 accountId);
    event UserAddedToSubscription(address user, uint256 serviceId, uint256 accountId);
    event SubscriptionUpdate(uint256 serviceId, uint256 accountId, uint256 numMembers, uint256 costPerMember);
    event CredentialsUpdated(address user, uint256 serviceId, uint256 accountId);
    
    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = 1000; // Initial tokens for testing
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    // Add this modifier to enforce subscription expiration
    modifier checkSubscriptionActive(uint256 serviceId) {
        if (userSubscriptions[msg.sender][serviceId].exists) {
            uint256 accountId = userSubscriptions[msg.sender][serviceId].accountId;
            SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
            
            // If expired, mark as inactive
            if (account.active && account.expirationTime < block.timestamp) {
                account.active = false;
                // Optionally update other state variables here
            }
            
            require(account.active, "Subscription has expired");
        } else {
            revert("Not subscribed to this service");
        }
        _;
    }


    
    
    function buyTokens(uint256 amount) external payable {
        require(msg.value >= amount * tokenPrice, "Insufficient payment");
        balanceOf[msg.sender] += amount;
    }
    
    // Helper to get a random account with available space
    function _getAvailableSubscriptionAccount(uint256 serviceId) internal view returns (uint256) {
        uint256[] memory activeAccounts = activeSubscriptionsByService[serviceId];
        uint256[] memory availableAccounts = new uint256[](activeAccounts.length);
        uint256 availableCount = 0;
        
        // Find accounts with available space
        for (uint i = 0; i < activeAccounts.length; i++) {
            uint256 accountId = activeAccounts[i];
            if (subscriptionAccounts[serviceId][accountId].members.length < maxUsersPerSubscription) {
                availableAccounts[availableCount] = accountId;
                availableCount++;
            }
        }
        
        // If no accounts have space, return 0 to signal a new account is needed
        if (availableCount == 0) {
            return 0;
        }
        
        // Random selection from available accounts
        // Rayn: Add additional entropy sources for randomisation
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            msg.sender, 
            blockhash(block.number - 1),
            block.prevrandao // For post-merge Ethereum
        ))) % availableCount;
        return availableAccounts[randomIndex];
    }
    
    // Create a new subscription account
    function _createSubscriptionAccount(uint256 serviceId) internal returns (uint256) {
        uint256 accountId = services[serviceId].subscriptionCount + 1;
        services[serviceId].subscriptionCount = accountId;
        
        // Initialize the subscription account in storage
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        account.active = true;
        account.expirationTime = block.timestamp + subscriptionDuration;
        
        // Add to active accounts
        activeSubscriptionsByService[serviceId].push(accountId);
        
        emit SubscriptionAccountCreated(serviceId, accountId);
        return accountId;
    }
    
    // Subscribe to a service - user will be assigned to an existing account with space or a new one
    function subscribe(uint256 serviceId) external {
        require(services[serviceId].exists, "Service does not exist");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        require(!userSubscriptions[msg.sender][serviceId].exists, "Already subscribed to this service");
        
        // Deduct token for subscription
        balanceOf[msg.sender] -= 1;
        
        // Try to find an available subscription account
        uint256 accountId = _getAvailableSubscriptionAccount(serviceId);
        
        // If no account available, create a new one
        if (accountId == 0) {
            accountId = _createSubscriptionAccount(serviceId);
        }
        
        // Add user to subscription account
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        account.members.push(msg.sender);
        account.isMember[msg.sender] = true;
        
        // Record user's subscription
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        userSub.exists = true;
        userSub.serviceId = serviceId;
        userSub.accountId = accountId;
        
        emit UserAddedToSubscription(msg.sender, serviceId, accountId);
    }
    
    // Store encrypted credentials for a subscription (encrypted with user's public key)
    function storeEncryptedCredentials(
        uint256 serviceId, 
        bytes calldata encryptedData
    ) external checkSubscriptionActive(serviceId) {
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        // Store encrypted credentials
        account.encryptedCredentials[msg.sender] = encryptedData;
        
        emit CredentialsUpdated(msg.sender, serviceId, accountId);
    }
    
    // Set base credentials for a subscription account (only owner can do this)
    function setBaseCredentials(
        uint256 serviceId, 
        uint256 accountId, 
        string calldata encryptedUsername, 
        string calldata encryptedPassword
    ) external onlyOwner {
        require(subscriptionAccounts[serviceId][accountId].active, "Subscription account not active");
        
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        account.encryptedUsername = encryptedUsername;
        account.encryptedPassword = encryptedPassword;
    }
    
    // Get encrypted credentials for a user
    function getEncryptedCredentials(uint256 serviceId) external view returns (bytes memory) {
        // We'll need to manually check subscription expiration instead of using the modifier
        // since modifiers with state changes can't be used with view functions
        
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        // Manual check for expiration
        require(account.active && account.expirationTime >= block.timestamp, "Subscription has expired");
        
        return account.encryptedCredentials[msg.sender];
    }
    
    // Check all subscriptions and expire those that have passed their time
    //function checkAndExpireSubscriptions() external {
      //  for (uint256 serviceId = 1; serviceId <= 100; serviceId++) {
        //    if (services[serviceId].exists) {
        //        uint256[] memory activeAccounts = activeSubscriptionsByService[serviceId];
      //          for (uint i = 0; i < activeAccounts.length; i++) {
     //               uint256 accountId = activeAccounts[i];
     //               SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
                    
     //               if (account.active && account.expirationTime < block.timestamp) {
    //                    account.active = false;
     //                   
    //                    // Also mark all members' subscriptions as inactive
    //                    for (uint j = 0; j < account.members.length; j++) {
    //                        address member = account.members[j];
    //                        userSubscriptions[member][serviceId].exists = false;
    //                    }
    //                }
          //      }
     //       }
      //  }
    //}
    
    // Renew a subscription account (extends expiration time)
    function renewSubscription(uint256 serviceId) external {
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        // Deduct token and extend expiration
        balanceOf[msg.sender] -= 1;
        account.expirationTime = block.timestamp + subscriptionDuration;
        account.active = true; // Ensure it's active
    }
    
    // Calculate cost per member for a specific subscription account
    function calculateCostPerMember(uint256 serviceId, uint256 accountId) external {
        require(services[serviceId].exists, "Service does not exist");
        require(subscriptionAccounts[serviceId][accountId].active, "Subscription account not active");
        
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        uint256 memberCount = account.members.length;
        
        require(memberCount > 0, "No members in subscription");
        uint256 costPerMember = services[serviceId].cost / memberCount;
        
        emit SubscriptionUpdate(serviceId, accountId, memberCount, costPerMember);
    }
    
    // Get members of a subscription account
    function getSubscriptionMembers(uint256 serviceId, uint256 accountId) external view returns (address[] memory) {
        return subscriptionAccounts[serviceId][accountId].members;
    }
    
    // Check if a subscription is active
    function isSubscriptionActive(address user, uint256 serviceId) external view returns (bool) {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        if (!userSub.exists) return false;
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        return account.active && account.expirationTime >= block.timestamp;
    }
    
    // Add a new service
    function addService(uint256 serviceId, string calldata symbol) external onlyOwner {
        require(!services[serviceId].exists, "Service already exists");
        
        services[serviceId].exists = true;
        services[serviceId].cost = 10 ether; // Default cost
        services[serviceId].symbol = symbol;
        services[serviceId].subscriptionCount = 0;
    }
    
    // Update service cost
    function updateServiceCost(uint256 serviceId, uint256 newCost) external onlyOwner {
        require(services[serviceId].exists, "Service does not exist");
        services[serviceId].cost = newCost;
    }
    
    // Update max users per subscription
    function updateMaxUsersPerSubscription(uint256 newMax) external onlyOwner {
        maxUsersPerSubscription = newMax;
    }


    // Rayn prevent reentrancy attack code
    bool private _locked;

    // Add a modifier to prevent reetrancy
    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentracnt call");
        _locked = true;
        _;
        _locked = false;
    }
    
    // Withdraw funds from contract and prevent reentrancy
    function withdrawFunds() external onlyOwner nonReentrant{
        uint256 amount = address(this).balance;
        // Update state before external call
        uint256 contractBalance = amount;
        amount = 0;
        
        // Perform external call after state updates
        (bool success, ) = owner.call{value: contractBalance}("");
        require(success, "Transfer failed");
    }
    
    // Get service details
    function getServiceDetails(uint256 serviceId) external view 
        returns (bool exists, uint256 cost, string memory symbol, uint256 subscriptionCount) {
        ServiceInfo storage service = services[serviceId];
        return (service.exists, service.cost, service.symbol, service.subscriptionCount);
    }
    
    // Get user's subscription details
    function getUserSubscriptionDetails(address user, uint256 serviceId) external view 
        returns (bool exists, uint256 accountId) {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        return (userSub.exists, userSub.accountId);
    }
    
    // Fallback function to receive ETH
    receive() external payable {}

    //Jayden's new code
    struct Proposal {
        address proposer;
        address userToKick;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 endTime;
        mapping(address => bool) hasVoted;
    }

    // New events
    event ProposalCreated(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId,
        address proposer,
        address userToKick
    );
    event VoteCast(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId,
        address voter,
        bool vote
    );
    event UserKicked(
        uint256 serviceId,
        uint256 accountId,
        address kickedUser
    );

    // New error
    error VotingPeriodEnded();
    error AlreadyVoted();
    error NotMember();

    // New functions
    function proposeToKickUser(
        uint256 serviceId,
        uint256 accountId,
        address userToKick
    ) external {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        require(account.isMember[msg.sender], "Not a member");
        require(account.isMember[userToKick], "User not in this account");
        require(userToKick != msg.sender, "Cannot propose yourself");

        // Rate limiting: Ensure the user waits at least 12 hours between proposals
        require(
            block.timestamp > lastProposalTime[msg.sender] + 12 hours,
            "Wait before proposing again"
        );

        lastProposalTime[msg.sender] = block.timestamp;
        
        uint256 proposalId = ++account.proposalCount;
        Proposal storage proposal = account.proposals[proposalId];
        
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
    ) external {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        Proposal storage proposal = account.proposals[proposalId];
        
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

    function executeProposal(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId
    ) external {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        Proposal storage proposal = account.proposals[proposalId];
        
        require(block.timestamp > proposal.endTime, "Voting ongoing");
        require(account.isMember[proposal.userToKick], "Already kicked");

        // SAFETY CHECK: ensure at least 2 members to avoid underflow
        require(account.members.length >= 2, "Not enough members to execute proposal");

        uint256 totalMembers = account.members.length - 1; // Exclude userToKick
        uint256 requiredVotes = (totalMembers / 2) + 1;
        
        if (proposal.yesVotes >= requiredVotes) {
            // Remove user from subscription
            for (uint256 i = 0; i < account.members.length; i++) {
                if (account.members[i] == proposal.userToKick) {
                    account.members[i] = account.members[account.members.length - 1];
                    account.members.pop();
                    break;
                }
            }
            
            account.isMember[proposal.userToKick] = false;
            delete account.encryptedCredentials[proposal.userToKick];
            delete userSubscriptions[proposal.userToKick][serviceId];
            
            emit UserKicked(serviceId, accountId, proposal.userToKick);
        }
    }
    function getProposalCount(uint256 serviceId, uint256 accountId) 
        external 
        view 
        returns (uint256) 
    {
        return subscriptionAccounts[serviceId][accountId].proposalCount;
    }

    function getProposal(uint256 serviceId, uint256 accountId, uint256 proposalId)
        external
        view
        returns (
            address proposer,
            address userToKick,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 endTime
        )
    {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        Proposal storage proposal = account.proposals[proposalId];

        return (
            proposal.proposer,
            proposal.userToKick,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.endTime
        );
    }
}