// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

/**
 * @title ServiceManager
 * @dev Manages subscription services
 */
contract ServiceManager is Ownable {
    struct ServiceInfo {
        bool exists;
        uint256 cost;
        string symbol;
        uint256 subscriptionCount;
    }
    
    mapping(uint256 => ServiceInfo) public services;
    
    event ServiceAdded(uint256 indexed serviceId, string symbol);
    event ServiceCostUpdated(uint256 indexed serviceId, uint256 newCost);
    
    function addService(uint256 serviceId, string calldata symbol) external onlyOwner {
        require(!services[serviceId].exists, "Service already exists");
        
        services[serviceId].exists = true;
        services[serviceId].cost = 10 ether; // Default cost
        services[serviceId].symbol = symbol;
        services[serviceId].subscriptionCount = 0;
        
        emit ServiceAdded(serviceId, symbol);
    }
    
    function updateServiceCost(uint256 serviceId, uint256 newCost) external onlyOwner {
        require(services[serviceId].exists, "Service does not exist");
        services[serviceId].cost = newCost;
        emit ServiceCostUpdated(serviceId, newCost);
    }
    
    function getServiceDetails(uint256 serviceId) external view 
        returns (bool exists, uint256 cost, string memory symbol, uint256 subscriptionCount) {
        ServiceInfo storage service = services[serviceId];
        return (service.exists, service.cost, service.symbol, service.subscriptionCount);
    }
    
    function incrementSubscriptionCount(uint256 serviceId) internal {
        require(services[serviceId].exists, "Service does not exist");
        services[serviceId].subscriptionCount += 1;
    }
}