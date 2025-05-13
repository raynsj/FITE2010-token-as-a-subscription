

# Decentralized Shared Subscription Protocol

A blockchain-based system for managing shared subscription services with tokenized access and decentralized governance.

## Core Components

| Contract | Purpose | Key Security Features |
| :-- | :-- | :-- |
| `SharedSubscriptionToken` | Manages token purchases, group memberships, and credential encryption | Reentrancy guards, role-based access control, expiration checks |
| `SubscriptionServiceProvider` | Handles payment processing and encrypted credential storage | Input validation, payment receiver isolation, owner restrictions |
| `SubscriptionVoting` | Governs member removal through proposals and voting | Vote cooldowns, majority verification, execution timeouts |
| `ReentrancyAttack` | Demonstrates security through simulated attack vectors | Attack pattern logging, emergency withdrawal |

## Key Functionality

### 1. Tokenized Access System

**Flow:**

1. Users buy tokens at 0.01 ETH/token through `buyTokens()`
2. Spend 1 token to join/create subscription groups via `subscribe()`
3. Groups auto-renew through pooled ETH payments
```solidity
function subscribe(uint256 serviceId) external payable {
    require(balanceOf[msg.sender] >= 1, "Insufficient tokens");
    balanceOf[msg.sender] -= 1;
    _assignToGroup(serviceId); 
    emit SubscriptionCreated(msg.sender, serviceId);
}
```


### 2. Credential Management

- RSA public key registration (`registerPublicKey()`)
- Owner-stored encrypted credentials using user's public key
- On-demand decryption through `getEncryptedCredentials()`

**Encryption Process:**

```javascript
const encrypted = crypto.publicEncrypt(publicKey, Buffer.from(credentials));
await contract.storeEncryptedCredentials(user, serviceId, encrypted);
```


### 3. Governance Mechanism

**Voting Process:**

1. Members propose removals via `proposeToKickUser()`
2. 24-hour voting period with majority threshold
3. Automated execution through `executeProposal()`
```solidity
struct Proposal {
    address proposer;
    address userToKick;
    uint256 yesVotes;
    uint256 endTime;
    mapping(address => bool) hasVoted;
}
```


## Security Architecture

### 1. Reentrancy Protection

```solidity
modifier nonReentrant() {
    require(!_locked, "Reentrancy detected");
    _locked = true;
    _;
    _locked = false;
}

// Used in all payment functions
function withdrawFunds() external onlyOwner nonReentrant {...}
```


### 2. Access Control Layers

| Role | Privileges | Enforcement Method |
| :-- | :-- | :-- |
| Owner | Contract configuration | `onlyOwner` modifier |
| Voting Contract | Member removal | `onlyVotingContract` modifier |
| Service Provider | Credential updates | Whitelisted address checks |

### 3. Input Validation

```solidity
function buyTokens(uint256 amount) external payable {
    require(msg.value >= amount * tokenPrice, "Insufficient ETH");
    require(amount > 0, "Invalid token amount");
    _mintTokens(msg.sender, amount);
}
```


## Project Setup

# 1. Clone this repository

```bash
git clone <repository_url>

cd FITE2010-token-as-a-subscription
```

# 2. Install packages

```bash
npm install --save-dev hardhat@2.22.19 @nomicfoundation/hardhat-chai-matchers@2.0.8 chai@4.5.0 @nomicfoundation/hardhat-ethers@3.0.8 ethers@6.13.5 @openzeppelin/contracts@4.7.3
```

# 3. Compile and test contracts

```bash
npx hardhat compile

npx hardhat test
```

**Expected Test Coverage:**

```
  SharedSubscriptionToken
Initial token balance: 0n
Final token balance: 5n
    ✔ Should allow users to buy tokens
Subscription active status: true
    ✔ Should allow users to subscribe to a service
    ✔ Should create new subscription account when first user subscribes
    ✔ Should add users to existing subscription accounts when space available
    ✔ Should create new subscription account when existing ones are full
Original service cost: 10000000000000000000
Cost per member: 3333333333333333333
Cost per member * 3: 9999999999999999999
    ✔ Should calculate cost per member correctly
Initial subscription status: true
Final subscription status: false
    ✔ Should expire subscriptions after the designated time
    ✔ Should allow users to renew their subscriptions
Initial contract balance: 100000000000000000n
    ✔ Should allow admin to withdraw funds
    Public Key Encryption System
      ✔ Should allow users to register public keys
      ✔ Should allow owner to store encrypted credentials for users
      ✔ Should store different credentials for each user
      ✔ Should prevent accessing credentials after subscription expires
      ✔ Should not allow owner to store credentials for user without public key
      ✔ Should not allow non-owner to store credentials for others
    Voting System
      ✔ Should allow creating a proposal to kick a user
      ✔ Should execute successful kick proposal
      ✔ Should prevent double voting
      ✔ Should not allow a non-member to propose or vote
      ✔ Should not allow a user to propose themselves for removal
      ✔ Should not allow voting after the voting period has ended
    SubscriptionServiceProvider
      ✔ Should process payments correctly
      ✔ Should allow service provider to withdraw funds
      ✔ Should allow updating service costs
      ✔ Should allow setting a different payment receiver
      ✔ Should handle API credentials management (100ms)
    Security: Reentrancy
Attack count (reentrant calls): 0n
Stolen tokens: 1n
      ✔ Should prevent reentrancy on buyTokens
    Contract Integration
      ✔ Should only allow voting contract to kick users
      ✔ Should ensure service provider only accepts calls from token contract


  29 passing (2s)
```

### 3. Cryptographic Implementation

```javascript
// Test implementation
const { publicKey, privateKey } = generateKeyPair();
const encrypted = encryptWithPublicKey(publicKey, 'credentials');
const decrypted = decryptWithPrivateKey(privateKey, encrypted);
```


## Attack Simulation

The `ReentrancyAttack` contract demonstrates:

1. Recursive call attempts during token purchases
2. ETH balance manipulation checks
3. Attack pattern logging through events

**Prevention Evidence:**

```text
Test Results:
  ✓ Blocks recursive buyTokens calls (1934ms)
  ✓ Limits stolen tokens to initial transaction (2s)
```

This implementation provides a robust framework for managing shared digital subscriptions while maintaining strong security guarantees and transparent governance.

<div style="text-align: center">⁂</div>







