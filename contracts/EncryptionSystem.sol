// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubscriptionManager.sol";

/**
 * @title EncryptionSystem
 * @dev Handles public key encryption and credential storage
 */
contract EncryptionSystem is SubscriptionManager {
    mapping(address => string) public userPublicKeys;
    mapping(uint256 => mapping(uint256 => mapping(address => bytes))) public encryptedCredentials;
    
    event PublicKeyRegistered(address user, string publicKey);
    event CredentialsUpdated(address user, uint256 serviceId, uint256 accountId);
    
    function registerPublicKey(string calldata publicKey) external virtual{
        require(bytes(publicKey).length > 0, "Public key cannot be empty");
        userPublicKeys[msg.sender] = publicKey;
        emit PublicKeyRegistered(msg.sender, publicKey);
    }
    
    function getPublicKey(address user) external view returns (string memory) {
        return userPublicKeys[user];
    }
    
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
        
        encryptedCredentials[serviceId][accountId][user] = encryptedData;
        
        emit CredentialsUpdated(user, serviceId, accountId);
    }
    
    function getEncryptedCredentials(uint256 serviceId) external view returns (bytes memory) {
        UserSubscription storage userSub = userSubscriptions[msg.sender][serviceId];
        require(userSub.exists, "Not subscribed to this service");
        
        uint256 accountId = userSub.accountId;
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        
        require(account.active && account.expirationTime >= block.timestamp, "Subscription has expired");
        
        return encryptedCredentials[serviceId][accountId][msg.sender];
    }
    
    function _removeEncryptedCredentials(uint256 serviceId, uint256 accountId, address user) internal {
        delete encryptedCredentials[serviceId][accountId][user];
    }
}