# FITE2010-token-as-a-subscription

Decentralized "Subscription-as-a-Token" Service
(Jayden)
Concept
This project introduces a decentralized subscription model where users purchase tokens to access services like Netflix and Spotify through platforms such as Bitrefill, CoinGate, and eGifter. Tokens represent time-bound subscription rights, eliminating the need for credit cards or personal identities. The system will be enhanced to allow users to request subscriptions to new platforms not currently on the blockchain, manage deposits for monthly fees, and distribute costs among subscribers.
Key Features
Tokenized Access: Users buy tokens to activate subscriptions for specific durations.
Automated Management: Smart contracts handle renewals and expirations.
Platform Integration: Enables decentralized payments for subscription services.
User-Requested Subscriptions: Users can request subscriptions to new platforms, with a deposit for the monthly fee.
Cost Distribution: The cost of subscriptions is divided equally among users subscribing to the same platform.
Fallback Mechanism: If subscription activation fails, a fallback function ensures refunds or alternative actions.
Smart Contract Functions
buyTokens(uint256 amount): Purchase tokens with Ether.
activateSubscription(address user, uint256 serviceId): Deduct tokens to activate subscriptions.
checkAndExpireSubscriptions(): Automatically expire subscriptions.
requestNewPlatform(address user, uint256 platformId): Users can request subscriptions to new platforms, with a deposit for the monthly fee.
checkSubscribers(uint256 platformId): Returns the number of users subscribing to a specific platform.
divideCost(uint256 platformId): Calculates and distributes the cost of subscriptions equally among users.
fallbackFunction(address user, uint256 platformId): Handles failed subscription activations.
Admin functions:
addService(uint256 serviceId): Add new services to the platform.
withdrawFunds(): Withdraw funds from the contract.
Events
SubscriptionUpdate(uint256 platformId, uint256 numSubscribers, uint256 costPerSubscriber): Notifies users about the number of subscribers and the cost per subscriber for a specific platform.
Evaluation Criteria
Innovation: Tokenized, decentralized subscription model with user-requested subscriptions.
Functionality: Automates subscription management securely, including cost distribution and fallback mechanisms.
Code Quality: Modular, secure, and readable Solidity code.
Usability: Easy interaction via Remix/Hardhat.

