// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SubscriptionServiceProvider
 * @dev A contract that simulates real-world service providers by offering
 * subscription services, accepting payments, and providing access credentials.
 * This acts as the demo service layer that would interface with actual API services.
 */
contract SubscriptionServiceProvider {
    // Contract owner address
    address public owner;
    
    // SharedSubscriptionToken contract address (trusted caller)
    address public tokenContractAddress;
    
    // Payment receiver address
    address public paymentReceiver;
    
    /**
     * @dev Information about a service offering
     * @param exists Whether the service exists
     * @param cost The full cost of the service (before sharing)
     * @param symbol Service identifier/symbol (e.g., "NFLX" for Netflix)
     * @param apiEndpoint Mock API endpoint for the service
     */
    struct ServiceInfo {
        bool exists;
        uint256 cost;
        string symbol;
        string apiEndpoint;
    }
    
    // Mapping of service ID to service information
    mapping(uint256 => ServiceInfo) public services;
    
    // Mapping of service ID and user address to their subscription status
    mapping(uint256 => mapping(address => bool)) public isSubscribed;
    
    // Mapping of service ID and user address to their encrypted API credentials
    mapping(uint256 => mapping(address => bytes)) private encryptedCredentials;
    
    // ==================== EVENTS ====================
    
    // Emitted when payment is received for a service
    event PaymentReceived(uint256 serviceId, address payer, uint256 amount);
    
    // Emitted when a new service is added
    event ServiceAdded(uint256 serviceId, string symbol, uint256 cost);
    
    // Emitted when service credentials are updated
    event CredentialsUpdated(uint256 serviceId, address user);
    
    // ==================== ERRORS ====================
    
    error ServiceNotFound();
    error Unauthorized();
    error InsufficientPayment();
    error NotSubscribed();
    
    /**
     * @dev Constructor function
     */
    constructor() {
        owner = msg.sender;
        paymentReceiver = msg.sender;
    }
    
    /**
     * @dev Restricts function access to the contract owner
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }
    
    /**
     * @dev Restricts function access to the token contract
     */
    modifier onlyTokenContract() {
        if (msg.sender != tokenContractAddress) revert Unauthorized();
        _;
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev Sets the address of the token contract
     * @param _tokenContractAddress Address of the SharedSubscriptionToken contract
     */
    function setTokenContractAddress(address _tokenContractAddress) external onlyOwner {
        tokenContractAddress = _tokenContractAddress;
    }
    
    /**
     * @dev Sets the payment receiver address
     * @param _paymentReceiver Address to receive payments
     */
    function setPaymentReceiver(address _paymentReceiver) external onlyOwner {
        paymentReceiver = _paymentReceiver;
    }
    
    /**
     * @dev Adds a new service to the platform
     * @param serviceId Unique identifier for the service
     * @param symbol Short identifier string for the service (e.g., "NFLX")
     * @param cost Cost of the service
     * @param apiEndpoint Mock API endpoint for the service
     */
    function addService(
        uint256 serviceId, 
        string calldata symbol, 
        uint256 cost,
        string calldata apiEndpoint
    ) external onlyOwner {
        if (services[serviceId].exists) revert("Service already exists");
        
        services[serviceId] = ServiceInfo({
            exists: true,
            cost: cost,
            symbol: symbol,
            apiEndpoint: apiEndpoint
        });
        
        emit ServiceAdded(serviceId, symbol, cost);
    }
    
    /**
     * @dev Updates the cost of an existing service
     * @param serviceId ID of the service to update
     * @param newCost New cost for the service
     */
    function updateServiceCost(uint256 serviceId, uint256 newCost) external onlyOwner {
        if (!services[serviceId].exists) revert ServiceNotFound();
        services[serviceId].cost = newCost;
    }
    
    /**
     * @dev Withdraws funds from the contract
     */
    function withdrawFunds() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = paymentReceiver.call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @dev Manually registers a user as subscribed (for testing)
     * Only callable by owner
     */
    function manuallyRegisterSubscriber(uint256 serviceId, address user) external onlyOwner {
        if (!services[serviceId].exists) revert ServiceNotFound();
        isSubscribed[serviceId][user] = true;
    }
    
    // ==================== TOKEN CONTRACT FUNCTIONS ====================
    
    /**
     * @dev Processes a payment for a subscription service
     * Can only be called by the token contract
     * @param serviceId ID of the service
     * @param user Address of the subscribing user
     * @return success Whether the payment was successful
     */
    function processPayment(uint256 serviceId, address user) external payable onlyTokenContract returns (bool success) {
        if (!services[serviceId].exists) revert ServiceNotFound();
        if (msg.value < services[serviceId].cost) revert InsufficientPayment();
        
        // Mark user as subscribed to this service
        isSubscribed[serviceId][user] = true;
        
        emit PaymentReceived(serviceId, user, msg.value);
        return true;
    }
    
    /**
     * @dev Stores encrypted credentials for a user
     * Only callable by the token contract
     * @param user Address of the user
     * @param serviceId ID of the service
     * @param encryptedData Encrypted credentials data
     */
    function storeEncryptedCredentials(
        address user,
        uint256 serviceId, 
        bytes calldata encryptedData
    ) external onlyTokenContract {
        if (!services[serviceId].exists) revert ServiceNotFound();
        
        // If the user is not subscribed, register them (this is needed because in our new architecture,
        // all members of a shared account should be marked as subscribed)
        if (!isSubscribed[serviceId][user]) {
            isSubscribed[serviceId][user] = true;
        }
        
        // Store encrypted credentials
        encryptedCredentials[serviceId][user] = encryptedData;
        
        emit CredentialsUpdated(serviceId, user);
    }
    
    /**
     * @dev Retrieves a user's encrypted credentials for a service
     * Only callable by the token contract
     * @param user Address of the user
     * @param serviceId ID of the service
     * @return Encrypted credentials bytes
     */
    function getEncryptedCredentials(address user, uint256 serviceId) 
        external 
        view 
        onlyTokenContract 
        returns (bytes memory) 
    {
        if (!services[serviceId].exists) revert ServiceNotFound();
        if (!isSubscribed[serviceId][user]) revert NotSubscribed();
        
        return encryptedCredentials[serviceId][user];
    }
    
    /**
     * @dev Cancels a user's subscription to a service
     * Only callable by the token contract
     * @param user Address of the user
     * @param serviceId ID of the service
     */
    function cancelSubscription(address user, uint256 serviceId) external onlyTokenContract {
        isSubscribed[serviceId][user] = false;
        delete encryptedCredentials[serviceId][user];
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev Gets details about a service
     * @param serviceId ID of the service
     * @return exists Whether the service exists
     * @return cost Cost of the service
     * @return symbol Symbol/identifier of the service
     * @return apiEndpoint Mock API endpoint for the service
     */
    function getServiceDetails(uint256 serviceId) external view 
        returns (bool exists, uint256 cost, string memory symbol, string memory apiEndpoint) 
    {
        ServiceInfo storage service = services[serviceId];
        return (service.exists, service.cost, service.symbol, service.apiEndpoint);
    }
    
    /**
     * @dev Checks if a user is subscribed to a service
     * @param serviceId ID of the service
     * @param user Address of the user
     * @return Whether the user is subscribed
     */
    function checkSubscriptionStatus(uint256 serviceId, address user) external view returns (bool) {
        return isSubscribed[serviceId][user];
    }
    
    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}