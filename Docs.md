# Contracts File Structure

## Base Contracts:

1. Ownable.sol - For ownership functionality
2. ReentrancyGuard.sol - Anti-reentrancy protection
3. TokenBase.sol - Basic token functionality

## Feature-specific Contracts:

1. SubscriptionManager.sol - Core subscription logic
2. VotingSystem.sol - Governance and voting
3. EncryptionSystem.sol - Public key and credential management
4. ServiceManager.sol - Service registration and management

## Main Contract:

SharedSubscriptionToken.sol - Inherits from all the above
