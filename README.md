# FITE2010-token-as-a-subscription

A blockchain-based solution that transforms subscription services into tokenized assets, enabling anonymous, decentralized access to popular platforms without credit cards or personal identities.

# Project Overview

This project introduces a revolutionary approach to subscription services by leveraging blockchain technology to create tokenized subscription rights. Users can purchase tokens to access services like Netflix and Spotify through integrated platforms such as Bitrefill, CoinGate, and eGifter without revealing personal information or using traditional payment methods.

Our system goes beyond basic token transactions by allowing users to request new subscription platforms, distribute costs among subscribers, and manage deposits for monthly fees through smart contracts.

# Key Features

Tokenized Access: Purchase tokens to activate time-bound subscription rights

Automated Management: Smart contracts handle subscription lifecycles including renewals and expirations

Cost Distribution: Subscription costs divided equally among users of the same platform

# Smart Contract Architecture

Our core functionality is implemented through the following smart contract functions:

```solidity
// User Functions
function buyTokens(uint256 amount) external payable;
function activateSubscription(address user, uint256 serviceId) external;
function checkAndExpireSubscriptions() external;
function requestNewPlatform(address user, uint256 platformId) external;
function checkSubscribers(uint256 platformId) external view returns (uint256);
function divideCost(uint256 platformId) external;

// Admin Functions
function addService(uint256 serviceId) external onlyOwner;
function withdrawFunds() external onlyOwner;

// Fallback Handling
function fallbackFunction(address user, uint256 platformId) external;
```

# Events

The system emits events to notify users about important changes:

```solidity
event SubscriptionUpdate(
    uint256 platformId, 
    uint256 numSubscribers, 
    uint256 costPerSubscriber
);
```







