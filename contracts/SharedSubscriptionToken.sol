// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Interface for interacting with the SubscriptionServiceProvider contract
 */
interface ISubscriptionServiceProvider {
    function processPayment(uint256 serviceId, address user) external payable returns (bool);
    function storeEncryptedCredentials(address user, uint256 serviceId, bytes calldata encryptedData) external;
    function getEncryptedCredentials(address user, uint256 serviceId) external view returns (bytes memory);
    function cancelSubscription(address user, uint256 serviceId) external;
    function getServiceDetails(uint256 serviceId) external view returns (bool, uint256, string memory, string memory);
    function checkSubscriptionStatus(uint256 serviceId, address user) external view returns (bool);
}

/**
 * @title SharedSubscriptionToken
 * @dev A contract that implements token-as-a-subscription functionality with shared accounts.
 * This contract manages subscription accounts and user membership, while interacting
 * with an external service provider contract that handles actual service credentials.
 */
contract SharedSubscriptionToken {
    // Contract owner address
    address public owner;
    
    // Price per token in ETH (0.01 ETH = 1 token)
    uint256 public tokenPrice = 0.01 ether;
    
    // Default subscription duration (30 days)
    uint256 public subscriptionDuration = 30 days;
    
    // Maximum users allowed in one subscription account
    uint256 public maxUsersPerSubscription = 5;
    
    // Address of the associated voting contract that manages governance
    address public votingContractAddress;
    
    // Address of the service provider contract
    address public serviceProviderAddress;
    
    // Service provider interface
    ISubscriptionServiceProvider public serviceProvider;
    
    /**
     * @dev Information about a shared subscription account
     * @param active Whether the subscription is currently active
     * @param expirationTime Timestamp when the subscription expires
     * @param members Array of addresses who are members of this subscription
     * @param isMember Mapping for quick lookup if an address is a member
     * @param serviceId ID of the service this account is subscribed to
     */
    struct SubscriptionAccount {
        bool active;
        uint256 expirationTime;
        address[] members;
        mapping(address => bool) isMember;
        uint256 serviceId;
    }
    
    /**
     * @dev Information about a user's subscription
     * @param exists Whether the user has an active subscription
     * @param serviceId ID of the service the user is subscribed to
     * @param accountId ID of the subscription account the user belongs to
     */
    struct UserSubscription {
        bool exists;
        uint256 serviceId;
        uint256 accountId;
    }
    
    // ==================== STATE VARIABLES ====================
    
    // Token balances for each address
    mapping(address => uint256) public balanceOf;
    
    // Double mapping of service ID and account ID to subscription account info
    mapping(uint256 => mapping(uint256 => SubscriptionAccount)) public subscriptionAccounts;
    
    // Double mapping of user address and service ID to user's subscription info
    mapping(address => mapping(uint256 => UserSubscription)) public userSubscriptions;
    
    // Mapping of service ID to array of active account IDs for that service
    mapping(uint256 => uint256[]) public activeSubscriptionsByService;
    
    // Mapping of service ID to subscription count
    mapping(uint256 => uint256) public subscriptionCounts;
    
    // Mapping of user address to their public key for encryption
    mapping(address => string) public userPublicKeys;
    
    // ==================== EVENTS ====================
    
    // Emitted when a new subscription account is created
    event SubscriptionAccountCreated(uint256 serviceId, uint256 accountId);
    
    // Emitted when a user is added to a subscription account
    event UserAddedToSubscription(address user, uint256 serviceId, uint256 accountId);
    
    // Emitted when subscription cost information is updated
    event SubscriptionUpdate(uint256 serviceId, uint256 accountId, uint256 numMembers, uint256 costPerMember);
    
    // Emitted when a user's credentials are updated
    event CredentialsUpdated(address user, uint256 serviceId, uint256 accountId);
    
    // Emitted when a user registers their public key
    event PublicKeyRegistered(address user, string publicKey);
    
    // Emitted when a user is kicked from a subscription account
    event UserKicked(uint256 serviceId, uint256 accountId, address kickedUser);
    
    /**
     * @dev Constructor function
     * Initializes the contract with the deployer as owner and gives them initial tokens for testing
     */
    constructor() {
        owner = msg.sender;
        balanceOf[msg.sender] = 1000; // Initial tokens for testing
    }
    
    // ==================== MODIFIERS ====================
    
    /**
     * @dev Restricts function access to the contract owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Restricts function access to the voting contract
     */
    modifier onlyVotingContract() {
        require(msg.sender == votingContractAddress, "Only voting contract can call this function");
        _;
    }

    /**
     * @dev Prevents reentrancy attacks
     */
    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev Sets the address of the voting contract
     * @param _votingContractAddress Address of the voting contract
     */
    function setVotingContractAddress(address _votingContractAddress) external onlyOwner {
        votingContractAddress = _votingContractAddress;
    }
    
    /**
     * @dev Sets the address of the service provider contract
     * @param _serviceProviderAddress Address of the service provider contract
     */
    function setServiceProviderAddress(address _serviceProviderAddress) external onlyOwner {
        serviceProviderAddress = _serviceProviderAddress;
        serviceProvider = ISubscriptionServiceProvider(_serviceProviderAddress);
    }
    
    /**
     * @dev Updates the maximum number of users allowed per subscription
     * @param newMax New maximum user count
     */
    function updateMaxUsersPerSubscription(uint256 newMax) external onlyOwner {
        maxUsersPerSubscription = newMax;
    }
    
    /**
     * @dev Withdraws funds from the contract
     * Includes reentrancy protection to prevent attacks
     */
    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        // Update state before external call
        uint256 contractBalance = amount;
        amount = 0;
        
        // Perform external call after state updates
        (bool success, ) = owner.call{value: contractBalance}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @dev Stores encrypted credentials for a user
     * @param user Address of the user
     * @param serviceId ID of the service
     * @param encryptedData Encrypted credentials data
     */
    function storeEncryptedCredentials(
        address user,
        uint256 serviceId, 
        bytes calldata encryptedData
    ) external onlyOwner {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        require(userSub.exists, "User not subscribed to this service");
        require(bytes(userPublicKeys[user]).length > 0, "User has not registered a public key");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        require(account.isMember[user], "Not a member of this account");
        
        // Send credentials to service provider
        serviceProvider.storeEncryptedCredentials(user, serviceId, encryptedData);
        
        emit CredentialsUpdated(user, serviceId, accountId);
    }
    
    // ==================== USER FUNCTIONS ====================
    
    /**
     * @dev Allows users to purchase tokens with ETH
     * @param amount Number of tokens to purchase
     */
    function buyTokens(uint256 amount) external payable {
        require(msg.value >= amount * tokenPrice, "Insufficient payment");
        balanceOf[msg.sender] += amount;
    }
    
    /**
     * @dev Allows a user to subscribe to a service
     * User will be assigned to an existing subscription account with space or a new one will be created
     * @param serviceId ID of the service to subscribe to
     */
    function subscribe(uint256 serviceId) external payable {
        // Verify the service exists by checking with service provider
        (bool exists, uint256 serviceCost, , ) = serviceProvider.getServiceDetails(serviceId);
        require(exists, "Service does not exist");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        require(!userSubscriptions[msg.sender][serviceId].exists, "Already subscribed to this service");
        
        // Deduct token for subscription
        balanceOf[msg.sender] -= 1;
        
        // Try to find an available subscription account
        uint256 accountId = _getAvailableSubscriptionAccount(serviceId);
        
        // If no account available, create a new one
        if (accountId == 0) {
            accountId = _createSubscriptionAccount(serviceId);
            
            // Process payment to service provider for new subscription account
            bool success = serviceProvider.processPayment{value: serviceCost}(serviceId, msg.sender);
            require(success, "Payment to service provider failed");
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
    
    /**
     * @dev Registers user's public key for encrypted credential storage
     * @param publicKey The user's public key in PEM format
     */
    function registerPublicKey(string calldata publicKey) external {
        require(bytes(publicKey).length > 0, "Public key cannot be empty");
        userPublicKeys[msg.sender] = publicKey;
        emit PublicKeyRegistered(msg.sender, publicKey);
    }
    
    /**
     * @dev Retrieves a user's encrypted credentials for a service
     * @param serviceId ID of the service
     * @return Encrypted credentials bytes
     */
    function getEncryptedCredentials(uint256 serviceId) external returns (bytes memory) {
        // First, update subscription status if needed
        _updateSubscriptionStatus(msg.sender, serviceId);
        
        // Now check if the subscription is active
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        require(account.active, "Subscription has expired");
        
        // Forward request to service provider
        return serviceProvider.getEncryptedCredentials(msg.sender, serviceId);
    }
    
    /**
     * @dev Renews a subscription by extending its expiration time
     * @param serviceId ID of the service to renew
     */
    function renewSubscription(uint256 serviceId) external payable {
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        // Get service cost
        (, uint256 serviceCost, , ) = serviceProvider.getServiceDetails(serviceId);
        
        // Process payment to service provider
        bool success = serviceProvider.processPayment{value: serviceCost}(serviceId, msg.sender);
        require(success, "Payment to service provider failed");
        
        // Deduct token and extend expiration
        balanceOf[msg.sender] -= 1;
        account.expirationTime = block.timestamp + subscriptionDuration;
        account.active = true; // Ensure it's active
    }
    
    /**
     * @dev Calculates the cost per member for a specific subscription account
     * @param serviceId ID of the service
     * @param accountId ID of the subscription account
     */
    function calculateCostPerMember(uint256 serviceId, uint256 accountId) external {
        // Check with service provider that the service exists
        (bool exists, uint256 serviceCost, , ) = serviceProvider.getServiceDetails(serviceId);
        require(exists, "Service does not exist");
        require(subscriptionAccounts[serviceId][accountId].active, "Subscription account not active");
        
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        uint256 memberCount = account.members.length;
        
        require(memberCount > 0, "No members in subscription");
        uint256 costPerMember = serviceCost / memberCount;
        
        emit SubscriptionUpdate(serviceId, accountId, memberCount, costPerMember);
    }
    
    /**
     * @dev Internal function to update the status of a subscription
     * Marks expired subscriptions as inactive
     * @param user Address of the user
     * @param serviceId ID of the service
     */
    function _updateSubscriptionStatus(address user, uint256 serviceId) internal {
        if (userSubscriptions[user][serviceId].exists) {
            uint256 accountId = userSubscriptions[user][serviceId].accountId;
            SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
            
            // If expired, mark as inactive
            if (account.active && account.expirationTime < block.timestamp) {
                account.active = false;
            }
        }
    }
    
    // ==================== VOTING CONTRACT FUNCTIONS ====================
    
    /**
     * @dev Kicks a user from a subscription account
     * Can only be called by the voting contract after a successful vote
     * @param serviceId ID of the service
     * @param accountId ID of the subscription account
     * @param userToKick Address of the user to kick
     */
    function kickUser(uint256 serviceId, uint256 accountId, address userToKick) external onlyVotingContract {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        require(account.isMember[userToKick], "User not in this account");
        
        // Remove user from subscription members array
        for (uint256 i = 0; i < account.members.length; i++) {
            if (account.members[i] == userToKick) {
                account.members[i] = account.members[account.members.length - 1];
                account.members.pop();
                break;
            }
        }
        
        account.isMember[userToKick] = false;
        delete userSubscriptions[userToKick][serviceId];
        
        // Notify service provider to cancel this user's access
        serviceProvider.cancelSubscription(userToKick, serviceId);
        
        emit UserKicked(serviceId, accountId, userToKick);
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev Gets the public key of a user
     * @param user Address of the user
     * @return Public key of the user
     */
    function getPublicKey(address user) external view returns (string memory) {
        return userPublicKeys[user];
    }
    
    /**
     * @dev Gets the members of a subscription account
     * @param serviceId ID of the service
     * @param accountId ID of the account
     * @return Array of member addresses
     */
    function getSubscriptionMembers(uint256 serviceId, uint256 accountId) external view returns (address[] memory) {
        return subscriptionAccounts[serviceId][accountId].members;
    }
    
    /**
     * @dev Checks if a subscription is active for a user
     * @param user Address of the user
     * @param serviceId ID of the service
     * @return Whether the subscription is active
     */
    function isSubscriptionActive(address user, uint256 serviceId) external view returns (bool) {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        if (!userSub.exists) return false;
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        // Check expiration without modifying state
        bool isActive = account.active && account.expirationTime >= block.timestamp;
        
        // Also check with service provider
        bool providerStatus = serviceProvider.checkSubscriptionStatus(serviceId, user);
        
        return isActive && providerStatus;
    }
    
    /**
     * @dev Gets a user's subscription details for a service
     * @param user Address of the user
     * @param serviceId ID of the service
     * @return exists Whether the user is subscribed
     * @return accountId ID of the account the user belongs to
     */
    function getUserSubscriptionDetails(address user, uint256 serviceId) external view 
        returns (bool exists, uint256 accountId) {
        UserSubscription storage userSub = userSubscriptions[user][serviceId];
        return (userSub.exists, userSub.accountId);
    }
    
    /**
     * @dev Checks if a user is a member of a specific subscription account
     * @param user Address of the user
     * @param serviceId ID of the service
     * @param accountId ID of the subscription account
     * @return Whether the user is a member
     */
    function isMemberOfAccount(address user, uint256 serviceId, uint256 accountId) external view returns (bool) {
        return subscriptionAccounts[serviceId][accountId].isMember[user];
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    // State variable for reentrancy guard
    bool private _locked;
    
    /**
     * @dev Helper function to get a random subscription account with available space
     * @param serviceId ID of the service
     * @return Account ID with space, or 0 if none found
     */
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
        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            msg.sender, 
            blockhash(block.number - 1),
            block.prevrandao // For post-merge Ethereum
        ))) % availableCount;
        return availableAccounts[randomIndex];
    }
    
    /**
     * @dev Creates a new subscription account
     * @param serviceId ID of the service
     * @return ID of the new account
     */
    function _createSubscriptionAccount(uint256 serviceId) internal returns (uint256) {
        uint256 accountId = subscriptionCounts[serviceId] + 1;
        subscriptionCounts[serviceId] = accountId;
        
        // Initialize the subscription account in storage
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        account.active = true;
        account.expirationTime = block.timestamp + subscriptionDuration;
        account.serviceId = serviceId;
        
        // Add to active accounts
        activeSubscriptionsByService[serviceId].push(accountId);
        
        emit SubscriptionAccountCreated(serviceId, accountId);
        return accountId;
    }
    
    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}